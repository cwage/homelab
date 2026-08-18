"""Minimal OpenBao KV v2 client over HTTP -- no bao CLI needed on workstations.

The bao binary only exists on the OpenBao server itself; workstations hold
BAO_ADDR/BAO_TOKEN in the repo-root .env (the same file the dockerized
ansible/tofu stacks read). This module resolves those -- real environment
variables win over .env -- and speaks the KV v2 API directly.
"""

import json
import os
import ssl
import urllib.error
import urllib.request

DEFAULT_ADDR = "https://bao.lan.quietlife.net:8200"
ENV_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".env")


def _conf():
    fromfile = {}
    if os.path.exists(ENV_FILE):
        with open(ENV_FILE) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, _, v = line.partition("=")
                    fromfile[k.strip()] = v.strip().strip('"').strip("'")

    def get(key, default=None):
        return os.environ.get(key) or fromfile.get(key) or default

    token = get("BAO_TOKEN")
    if not token:
        raise SystemExit("BAO_TOKEN not set in the environment or the repo "
                         ".env -- see docs/openbao-secrets.md")
    skip = (get("BAO_SKIP_VERIFY", "") or "").lower() in ("1", "true", "yes")
    return get("BAO_ADDR", DEFAULT_ADDR).rstrip("/"), token, skip


def _data_url(addr, path):
    # "kv/infra/foo" -> "<addr>/v1/kv/data/infra/foo" (KV v2 inserts /data/)
    mount, _, rest = path.partition("/")
    return f"{addr}/v1/{mount}/data/{rest}"


def _request(method, path, body=None):
    addr, token, skip = _conf()
    req = urllib.request.Request(
        _data_url(addr, path), method=method, data=body,
        headers={"X-Vault-Token": token, "Content-Type": "application/json"},
    )
    ctx = ssl._create_unverified_context() if skip else None
    try:
        with urllib.request.urlopen(req, context=ctx, timeout=15) as resp:
            return json.load(resp)
    except urllib.error.HTTPError as e:
        raise SystemExit(f"OpenBao {method} {path}: HTTP {e.code} "
                         f"{e.read().decode(errors='replace').strip()}")
    except urllib.error.URLError as e:
        raise SystemExit(f"cannot reach OpenBao at {addr}: {e.reason}")


def kv_get(path):
    """Return the secret at `path` (e.g. 'kv/infra/foo') as a dict."""
    return _request("GET", path)["data"]["data"]


def kv_put(path, mapping):
    """Replace the secret at `path` with `mapping` (KV v2 put semantics)."""
    _request("POST", path, json.dumps({"data": mapping}).encode())
