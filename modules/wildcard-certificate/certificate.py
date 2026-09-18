"""Renew the LAN wildcard through lego/Bao; independently monitor live TLS.

Only the renewal command reads credentials. Never print API response bodies,
subprocess output, or exception strings: they may contain credentials.
"""

import datetime
import hashlib
import json
import os
from pathlib import Path
import socket
import ssl
import subprocess
import sys
import time
import urllib.error
import urllib.request


class JobError(Exception):
    """An explicitly safe, operator-facing error message."""


def run(args, **kwargs):
    result = subprocess.run(args, capture_output=True, check=False, **kwargs)
    if result.returncode:
        raise JobError(f"{args[0]} failed (exit {result.returncode}); output withheld")
    return result.stdout


def certificate_info(pem):
    leaf = pem.split("-----END CERTIFICATE-----", 1)[0] + "-----END CERTIFICATE-----\n"
    fingerprint = hashlib.sha256(ssl.PEM_cert_to_DER_cert(leaf)).hexdigest()
    enddate = run(["openssl", "x509", "-noout", "-enddate"], input=leaf.encode())
    expires = ssl.cert_time_to_seconds(enddate.decode().strip().split("=", 1)[1])
    return fingerprint, expires


def probe(endpoint):
    # Verify chain, hostname AND validity, with SNI. DNS/connection/TLS errors
    # are failures, never a misleading "certificate has plenty of time".
    context = ssl.create_default_context()
    with socket.create_connection(
        (endpoint["host"], endpoint["port"]), timeout=10
    ) as sock:
        with context.wrap_socket(sock, server_hostname=endpoint["host"]) as conn:
            der = conn.getpeercert(binary_form=True)
            cert = conn.getpeercert()
            if der is None or cert is None or not isinstance(cert.get("notAfter"), str):
                raise ValueError("Listener did not return a certificate with an expiry")
            fingerprint = hashlib.sha256(der).hexdigest()
            not_after = cert["notAfter"]
            assert isinstance(not_after, str)
            expires = ssl.cert_time_to_seconds(not_after)
            return fingerprint, expires


def bao_request(cfg, payload=None):
    # Read on every request: the agent may replace its token during a run.
    token = Path(cfg["token_file"]).read_text().strip()
    if not token:
        raise JobError("OpenBao agent token is empty")
    request = urllib.request.Request(
        cfg["bao_url"] + "/v1/kv/data/infra/certs/" + cfg["domain"],
        data=None if payload is None else json.dumps(payload).encode(),
        headers={"X-Vault-Token": token, "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        operation = "read" if payload is None else "write"
        raise JobError(
            f"OpenBao certificate {operation} failed (HTTP {error.code})"
        ) from None


def publish(cfg, stored, cert_dir):
    domain = cfg["domain"]
    cert = cert_dir / f"_.{domain}.crt"
    key = cert_dir / f"_.{domain}.key"
    issuer = cert_dir / f"_.{domain}.issuer.crt"
    pem = cert.read_text()
    fingerprint, expires = certificate_info(pem)
    _, old_expires = certificate_info(stored["data"]["data"]["certificate"])
    if expires <= old_expires or expires <= time.time() + cfg["renew_days"] * 86400:
        raise JobError(
            "Issued certificate does not extend validity beyond the renewal window"
        )
    # Reject staging certs, mismatched keys and unexpected names before upload.
    context = ssl.create_default_context()
    context.load_cert_chain(cert, key)
    for hostname in [domain, "*." + domain]:
        run(["openssl", "x509", "-in", str(cert), "-noout", "-checkhost", hostname])
    run(
        [
            "openssl",
            "verify",
            "-purpose",
            "sslserver",
            "-untrusted",
            str(issuer),
            str(cert),
        ]
    )
    data = dict(stored["data"]["data"])
    data.update(
        certificate=pem,
        private_key=key.read_text(),
        issuer=issuer.read_text(),
        expires=datetime.datetime.fromtimestamp(
            expires, datetime.timezone.utc
        ).strftime("%b %d %H:%M:%S %Y GMT"),
        domain=domain,
    )
    # CAS prevents overwriting a concurrent manual renewal. A conflict fails
    # safely; tomorrow's run re-reads Bao before deciding what to do.
    bao_request(
        cfg, {"options": {"cas": stored["data"]["metadata"]["version"]}, "data": data}
    )
    print("Renewed certificate stored in OpenBao", flush=True)
    return fingerprint


def verify_propagation(cfg, fingerprint):
    deadline = time.monotonic() + cfg["propagation_seconds"]
    while True:
        pending = []
        for endpoint in cfg["endpoints"]:
            try:
                observed, _ = probe(endpoint)
                if observed == fingerprint:
                    continue
            except (OSError, ValueError, KeyError):
                pass
            pending.append(f"{endpoint['host']}:{endpoint['port']}")
        if not pending:
            print("Bao and Traefik serve the expected certificate", flush=True)
            return
        if time.monotonic() >= deadline:
            raise JobError(
                "Certificate propagation failed: "
                + ", ".join(pending)
                + "; inspect agent delivery and reload hooks (no remediation restart attempted)"
            )
        time.sleep(min(30, max(0, deadline - time.monotonic())))


def renew(cfg):
    state = Path(cfg["state_dir"])
    cert_dir = state / "certs" / "certificates"
    cert_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    stored = bao_request(cfg)
    fingerprint, expires = certificate_info(stored["data"]["data"]["certificate"])
    local_cert = cert_dir / f"_.{cfg['domain']}.crt"
    local_expires = 0
    if local_cert.exists():
        _, local_expires = certificate_info(local_cert.read_text())

    if (
        local_expires > expires
        and local_expires > time.time() + cfg["renew_days"] * 86400
    ):
        # A prior issuance succeeded but its Bao write failed. Reuse it even
        # if the currently stored cert is still outside the renewal window.
        print("Retrying publication of the already-issued certificate", flush=True)
        fingerprint = publish(cfg, stored, cert_dir)
    elif expires <= time.time() + cfg["renew_days"] * 86400:
        print("Wildcard certificate is due for renewal", flush=True)
        # Reuse the workstation's pinned Compose definition. --project-directory
        # resolves ./certs into the persistent production state directory.
        # File-backed Cloudflare credentials never enter argv or Docker's env.
        env = dict(os.environ, UID="0", GID="0")
        command = [
            "docker",
            "compose",
            "--project-name",
            "wildcard-certificate",
            "--project-directory",
            str(state),
            "-f",
            cfg["compose_file"],
            "run",
            "--rm",
            "-T",
            "--no-deps",
            "--name",
            "wildcard-renewal-lego",
            "-v",
            cfg["cloudflare_token_file"] + ":/run/secrets/cloudflare-token:ro",
            "-e",
            "CF_DNS_API_TOKEN_FILE=/run/secrets/cloudflare-token",
            "lego",
            "--accept-tos",
            "--email=" + cfg["email"],
            "--server=https://acme-v02.api.letsencrypt.org/directory",
            "--dns=cloudflare",
            "--dns.resolvers=1.1.1.1:53",
            "--domains=*." + cfg["domain"],
            "--domains=" + cfg["domain"],
        ]
        if local_cert.exists():
            # The systemd timer already adds jitter. Bound runtime here.
            command += [
                "renew",
                "--days=" + str(cfg["renew_days"]),
                "--no-random-sleep",
            ]
        else:
            command += ["run"]
        run(command, env=env, timeout=1200)
        fingerprint = publish(cfg, stored, cert_dir)
    else:
        print("Stored wildcard certificate is outside the renewal window", flush=True)
    # Also runs when issuance is unnecessary: catches a previous upload whose
    # propagation stalled, and manual changes made since our last run.
    verify_propagation(cfg, fingerprint)


def notify(cfg, endpoint, condition, priority):
    address = f"{endpoint['host']}:{endpoint['port']}"
    request = urllib.request.Request(
        cfg["topic"],
        data=f"{address}: {condition}".encode(),
        headers={
            "Title": "Homelab TLS certificate",
            "Priority": priority,
            "Tags": "warning",
        },
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        response.read()


def save_state(path, state):
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(state))
    temporary.replace(path)


def monitor(cfg):
    path = Path(cfg["state_dir"]) / "alerts.json"
    state = json.loads(path.read_text()) if path.exists() else {}
    notification_failed = False
    for endpoint in cfg["endpoints"]:
        identity = f"{endpoint['host']}:{endpoint['port']}"
        try:
            fingerprint, expires = probe(endpoint)
            days = (expires - time.time()) / 86400
            tier = next((limit for limit in [2, 7, 21] if days <= limit), None)
            key = None if tier is None else f"{fingerprint}:{tier}"
            condition = f"certificate expires within {tier} days"
            priority = {2: "urgent", 7: "high", 21: "default"}[tier or 21]
        except (OSError, ValueError, KeyError):
            key = "probe-failed"
            condition = "TLS probe failed (DNS, connection, trust, hostname or validity); check the live listener"
            priority = "urgent"
        if key is None:
            state.pop(identity, None)
        elif state.get(identity) != key:
            try:
                notify(cfg, endpoint, condition, priority)
            except OSError:
                # Do not mark an undelivered alert as sent; retry next run.
                notification_failed = True
                continue
            state[identity] = key
            print(f"Sent TLS alert for {identity}: {condition}", flush=True)
        save_state(path, state)
    if notification_failed:
        raise JobError("Could not deliver one or more TLS alerts; they remain pending")


def main():
    os.umask(0o077)
    try:
        cfg = json.loads(Path(sys.argv[2]).read_text())
        {"renew": renew, "monitor": monitor}[sys.argv[1]](cfg)
    except JobError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    except Exception as error:
        # Never print arbitrary exceptions from HTTP/ACME libraries: their
        # messages can contain response bodies, request headers or secrets.
        print(
            f"ERROR: certificate job failed ({type(error).__name__}); check credentials, connectivity and configuration",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
