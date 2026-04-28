{ config, lib, pkgs, ... }:

{
  networking.hostName = "bao2";

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
      node_id = "bao2"
    }

    api_addr     = "https://bao2.lan.quietlife.net:8200"
    cluster_addr = "https://bao2.lan.quietlife.net:8201"
  '';

  # --- OpenBao agent for secrets (cwage password hash) ---
  # Fetches from bao.lan.quietlife.net which resolves to this host. The agent
  # waits and retries if the local server is sealed.
  homelab.openbao-agent = {
    enable = true;
    tlsSkipVerify = false;
    roleId = "9f69c83d-c515-58d5-20aa-260e2f63a507";
    secrets = {
      cwage-password-hash = {
        path = "kv/data/infra/users/cwage";
        field = "password_hash";
        destination = "/etc/secrets/cwage-password-hash";
      };
    };
  };

  systemd.services.openbao = {
    description = "OpenBao server";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    # Don't start until TLS materials are staged out-of-band on first boot
    unitConfig.ConditionPathExists = "/var/lib/openbao/tls/tls.crt";

    serviceConfig = {
      User = "openbao";
      Group = "openbao";
      ExecStart = "${pkgs.openbao}/bin/bao server -config=/etc/openbao-server/openbao.hcl";
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
  # Mirrors the cron job that ran on the previous Debian VM. Token must be
  # staged manually at /etc/openbao/backup-token (mode 0600 root:root).
  # Mint with:
  #   bao token create -policy=backup -no-default-policy -orphan \
  #     -period=8760h -display-name="bao2-backup" -field=token \
  #     | sudo tee /etc/openbao/backup-token >/dev/null
  #   sudo chmod 0600 /etc/openbao/backup-token

  fileSystems."/mnt/backups" = {
    device = "10.10.15.4:/volume1/homelab-backups";
    fsType = "nfs";
    options = [ "noatime" "_netdev" "nofail" ];
  };

  systemd.services.openbao-backup = {
    description = "OpenBao Raft snapshot backup";
    path = with pkgs; [ openbao coreutils gnugrep findutils ];
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

      TOKEN_FILE="/etc/openbao/backup-token"
      if [[ -f "''${TOKEN_FILE}" ]]; then
        export BAO_TOKEN="$(cat "''${TOKEN_FILE}")"
      else
        echo "Backup token file not found: ''${TOKEN_FILE}"
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
      bao operator raft snapshot save "''${SNAPSHOT_FILE}"
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
