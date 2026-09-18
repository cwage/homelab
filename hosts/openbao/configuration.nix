{ config, lib, pkgs, ... }:

let
  # Runbook for the Raft snapshot job's auth. Referenced from the backup
  # script's log output (and therefore the ntfy failure notification).
  backupDocs = "https://github.com/cwage/homelab/blob/master/docs/openbao.md#troubleshooting-snapshot-fails-with-403";
in
{
  networking.hostName = "bao";

  # Prevent cloud-init from overriding the hostname after rebuild
  # (same workaround as dns1)
  environment.etc."cloud/cloud.cfg.d/99-preserve-hostname.cfg".text = ''
    preserve_hostname: true
  '';

  # Resolve via dns1 (NSD)
  networking.nameservers = [ "10.10.15.15" ];

  # --- OpenBao server ---

  # bao CLI on PATH for interactive operations on the server itself
  environment.systemPackages = [ pkgs.openbao ];

  users.groups.openbao = {};
  users.users.openbao = {
    isSystemUser = true;
    group = "openbao";
    home = "/var/lib/openbao";
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/openbao      0750 openbao openbao -"
    "d /var/lib/openbao/data 0750 openbao openbao -"
    "d /var/lib/openbao/tls  0750 openbao openbao -"
  ];

  # Server config. Not sensitive (paths only); world-readable is fine.
  # Lives outside /etc/openbao/ because that dir is 0750 root:root (managed by
  # the openbao-agent module) and the openbao server user can't traverse it.
  environment.etc."openbao-server/openbao.hcl".text = ''
    ui = true

    listener "tcp" {
      address       = "0.0.0.0:8200"
      tls_cert_file = "/var/lib/openbao/tls/tls.crt"
      tls_key_file  = "/var/lib/openbao/tls/tls.key"
    }

    storage "raft" {
      path    = "/var/lib/openbao/data"
      node_id = "bao"
    }

    api_addr     = "https://bao.lan.quietlife.net:8200"
    cluster_addr = "https://bao.lan.quietlife.net:8201"
  '';

  # --- OpenBao agent for secrets ---
  # Connects via loopback with TLS verification disabled to break the
  # chicken-and-egg: bao's own TCP listener uses the very TLS cert this agent
  # is responsible for refreshing. Loopback-only means there's no MITM concern,
  # and skipping verification means an expired cert can still be replaced.
  # The agent waits and retries if the local server is sealed.
  homelab.openbao-agent = {
    enable = true;
    address = "https://localhost:8200";
    tlsSkipVerify = true;
    roleId = "9f69c83d-c515-58d5-20aa-260e2f63a507";
    secrets = {
      cwage-password-hash = {
        path = "kv/data/infra/users/cwage";
        field = "password_hash";
        destination = "/etc/secrets/cwage-password-hash";
      };

      # LE wildcard cert delivery for bao's own TCP listener. The cert dir
      # is created and owned by the openbao server module above, so we tell
      # the agent module not to redeclare it.
      tls-cert = {
        path = "kv/data/infra/certs/lan.quietlife.net";
        field = "certificate";
        destination = "/var/lib/openbao/tls/tls.crt";
        owner = "openbao";
        group = "openbao";
        permissions = "0644";
        manageDestinationDir = false;
      };
      tls-key = {
        path = "kv/data/infra/certs/lan.quietlife.net";
        field = "private_key";
        destination = "/var/lib/openbao/tls/tls.key";
        owner = "openbao";
        group = "openbao";
        permissions = "0600";
        manageDestinationDir = false;
        # Command on the key, which sorts after tls-cert and is therefore
        # rendered second by openbao-agent (templates are emitted in
        # alphabetical order of the secret name and consul-template
        # processes them sequentially — see modules/openbao-agent.nix).
        # `reload` (NOT reload-or-restart) — SIGHUP re-reads TLS in place
        # without re-sealing. A restart would leave openbao sealed and
        # require manual unseal, so we accept that a hard reload failure
        # silently leaves the old cert active until the next render cycle.
        command = "systemctl reload openbao";
      };
    };
  };

  systemd.services.openbao = {
    description = "OpenBao server";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    # Reload (SIGHUP) on unit changes instead of NixOS's default restart.
    # A restart leaves openbao sealed and requires manual unseal — too high
    # a cost for routine config tweaks. SIGHUP re-reads listener TLS in
    # place; binary upgrades that genuinely need a restart are rare and can
    # be handled manually with `systemctl restart openbao && bao operator
    # unseal …`.
    reloadIfChanged = true;

    # Don't start until TLS materials are staged out-of-band on first boot.
    # Both files required: missing key would crash-loop the server.
    unitConfig.ConditionPathExists = [
      "/var/lib/openbao/tls/tls.crt"
      "/var/lib/openbao/tls/tls.key"
    ];

    serviceConfig = {
      User = "openbao";
      Group = "openbao";
      ExecStart = "${pkgs.openbao}/bin/bao server -config=/etc/openbao-server/openbao.hcl";
      # SIGHUP makes openbao re-read TLS files on disk WITHOUT re-sealing —
      # what we want when openbao-agent rotates the cert under us. A restart
      # would leave openbao sealed and require manual unseal.
      ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
      Restart = "on-failure";
      RestartSec = "5s";
      ProtectSystem = "strict";
      ReadWritePaths = [ "/var/lib/openbao" ];
      ProtectHome = true;
      NoNewPrivileges = true;
      PrivateTmp = true;
    };
  };

  # --- Daily Raft snapshot backup ---
  # Mirrors the cron job that ran on the previous Debian VM. Authenticates
  # with openbao-agent's own AppRole token (the sink file the agent keeps
  # renewed for as long as it runs), so there is no long-lived token to
  # stage or rotate. The `backup` policy (read sys/storage/raft/snapshot)
  # must be attached to this host's AppRole role — see
  # docs/openbao.md#backup-policy-setup-one-time.

  fileSystems."/mnt/backups" = {
    device = "10.10.15.4:/volume1/homelab-backups";
    fsType = "nfs";
    options = [ "noatime" "_netdev" "nofail" ];
  };

  homelab.ntfy = {
    enable = true;
    topic = "https://ntfy.sh/cwage-homelab-backup";
  };
  homelab.staleness.enable = true;
  homelab.wildcardCertificate.monitor.enable = true;

  systemd.services.openbao-backup = {
    description = "OpenBao Raft snapshot backup";
    path = with pkgs; [ openbao coreutils gnugrep findutils ];
    after = [ "openbao-agent.service" ];
    # Refuse to run if the NFS share isn't mounted — otherwise snapshots
    # would silently land on the root filesystem.
    unitConfig = {
      RequiresMountsFor = "/mnt/backups";
      OnFailure = [ "notify-failure@%n.service" ];
      OnSuccess = [ "notify-success@%n.service" ];
    };
    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };
    script = ''
      set -euo pipefail

      BACKUP_DIR="/mnt/backups/vm/openbao"
      RETENTION_DAYS=30
      TIMESTAMP=$(date +%Y%m%d-%H%M%S)
      SNAPSHOT_FILE="''${BACKUP_DIR}/openbao-''${TIMESTAMP}.snap"

      export BAO_ADDR="https://127.0.0.1:8200"
      export BAO_SKIP_VERIFY=true

      # openbao-agent's auto-auth token (modules/openbao-agent.nix). Root-only
      # via the 0750 runtime dir; the agent renews it, so it never expires
      # while the agent is up.
      AGENT_TOKEN="/run/openbao-agent/token"
      if [[ -s "''${AGENT_TOKEN}" ]]; then
        export BAO_TOKEN="$(cat "''${AGENT_TOKEN}")"
      else
        echo "openbao-agent token sink missing or empty: ''${AGENT_TOKEN}"
        echo "Is openbao-agent.service running? See ${backupDocs}"
        exit 1
      fi

      seal_output=$(bao status 2>&1 || true)
      if echo "''${seal_output}" | grep -q "Sealed.*false"; then
        :
      elif echo "''${seal_output}" | grep -q "Sealed.*true"; then
        echo "OpenBao is sealed, skipping backup"
        exit 0
      else
        echo "Failed to determine OpenBao seal status, aborting:"
        echo "''${seal_output}"
        exit 1
      fi

      mkdir -p "''${BACKUP_DIR}"
      chmod 0755 "''${BACKUP_DIR}"

      echo "Taking Raft snapshot to ''${SNAPSHOT_FILE}"
      if ! bao operator raft snapshot save "''${SNAPSHOT_FILE}"; then
        # The CLI opens the output file before making the request, so a
        # failed save leaves an empty .snap behind that looks like a backup.
        rm -f "''${SNAPSHOT_FILE}"
        echo "Snapshot failed. A 403 'permission denied' above means the agent's token lacks the 'backup' policy:"
        echo "re-attach it to this host's AppRole role and restart openbao-agent. See ${backupDocs}"
        exit 1
      fi
      chmod 0644 "''${SNAPSHOT_FILE}"

      echo "Removing backups older than ''${RETENTION_DAYS} days"
      find "''${BACKUP_DIR}" -name "openbao-*.snap" -type f -mtime +''${RETENTION_DAYS} -delete

      echo "Backup completed successfully"
    '';
  };

  systemd.timers.openbao-backup = {
    description = "Daily OpenBao Raft snapshot";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 00:30:00";
      Persistent = true;
    };
  };
}
