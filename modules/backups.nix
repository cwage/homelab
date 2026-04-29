{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.backups;

  # Shared rclone exclude patterns used by both b2 and local sweeps.
  rcloneExcludes = [
    "@eaDir/**"
    "#recycle/**"
    "*.db-wal"
    "*.db-shm"
    "**/logs/**"
    "Downloads/incomplete/**"
  ];

  rcloneFlagsArray = ''
    RCLONE_FLAGS=(
      --log-level INFO
      ${lib.concatMapStringsSep "\n      "
        (e: "--exclude ${lib.escapeShellArg e}")
        rcloneExcludes}
    )
  '';

  shellPathArray = name: paths: ''
    ${name}=(
      ${lib.concatMapStringsSep "\n      " lib.escapeShellArg paths}
    )
  '';

  # Common script preamble for the b2/local rclone sweeps.
  rcloneSweepScript = { target, dest, paths, preflightExtra ? "", credsBlock ? "" }: ''
    set -euo pipefail

    START_TIME=$(date +%s)
    NAS_ROOT=${lib.escapeShellArg cfg.nasRoot}
    DEST=${lib.escapeShellArg dest}
    ${shellPathArray "PATHS" paths}

    ${preflightExtra}

    ${credsBlock}

    ${rcloneFlagsArray}

    FAILED=()
    SUCCEEDED=()

    echo "Starting ${target} backup — ''${#PATHS[@]} path(s)"

    for path in "''${PATHS[@]}"; do
      src="$NAS_ROOT/$path"
      ${if target == "B2"
        then ''dest_path="b2crypt:$path"''
        else ''dest_path="$DEST/$path"''}

      if [[ ! -d "$src" ]]; then
        echo "WARNING: missing source: $src"
        FAILED+=("$path (not found)")
        continue
      fi

      echo "Syncing: $src -> $dest_path"
      if rclone sync "$src" "$dest_path" "''${RCLONE_FLAGS[@]}"; then
        echo "OK: $path"
        SUCCEEDED+=("$path")
      else
        echo "FAILED: $path"
        FAILED+=("$path")
      fi
    done

    DURATION=$(( $(date +%s) - START_TIME ))
    echo "---"
    echo "Backup complete (${target}): ''${#SUCCEEDED[@]} succeeded, ''${#FAILED[@]} failed (''${DURATION}s)"

    if [[ ''${#FAILED[@]} -gt 0 ]]; then
      echo "Failed paths:"
      for p in "''${FAILED[@]}"; do echo "  - $p"; done
      exit 1
    fi
  '';

  notifyHooks = {
    OnFailure = [ "notify-failure@%n.service" ];
    OnSuccess = [ "notify-success@%n.service" ];
  };
in
{
  options.homelab.backups = {
    nasRoot = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/nas";
      description = "Root path under which all NAS shares are mounted.";
    };

    b2 = {
      enable = lib.mkEnableOption "Daily encrypted Backblaze B2 sync";

      onCalendar = lib.mkOption {
        type = lib.types.str;
        default = "*-*-* 03:40:00";
        description = "systemd OnCalendar expression for the B2 sync timer.";
      };

      paths = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        example = [ "Pictures" "Documents" ];
        description = "NAS share paths to sync, relative to nasRoot.";
      };

      cryptRemote = lib.mkOption {
        type = lib.types.str;
        default = "b2:cwagenas-backup";
        description = "Underlying rclone remote that the b2crypt overlay wraps.";
      };

      secretsDir = lib.mkOption {
        type = lib.types.str;
        default = "/etc/secrets/backup";
        description = ''
          Directory holding openbao-agent-templated credential files.
          Required: b2-account, b2-key, b2crypt-pw.
          Optional: b2crypt-pw2 (only if rclone crypt was configured with a
          custom salt — most setups don't use one).
        '';
      };
    };

    local = {
      enable = lib.mkEnableOption "Daily local backup sync to USB drive";

      onCalendar = lib.mkOption {
        type = lib.types.str;
        default = "*-*-* 02:00:00";
        description = "systemd OnCalendar expression for the local sync timer.";
      };

      paths = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "NAS share paths to sync, relative to nasRoot.";
      };

      destination = lib.mkOption {
        type = lib.types.str;
        default = "/mnt/nasbak";
        description = "Local mount point that receives the unencrypted copy.";
      };
    };

    configs = {
      enable = lib.mkEnableOption "Daily container volume snapshots";

      onCalendar = lib.mkOption {
        type = lib.types.str;
        default = "*-*-* 03:00:00";
        description = "systemd OnCalendar expression for the configs snapshot timer.";
      };

      composeFile = lib.mkOption {
        type = lib.types.str;
        default = "/opt/stacks/docker-compose.yml";
        description = "Path to the docker compose file describing the stack.";
      };

      destination = lib.mkOption {
        type = lib.types.str;
        default = "/mnt/nas/containers-configs";
        description = "Per-service volume snapshots are written under this directory.";
      };

      services = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Compose service name.";
            };
            mount = lib.mkOption {
              type = lib.types.str;
              description = "In-container mount point of the named volume to snapshot.";
            };
          };
        });
        default = [];
        example = [ { name = "jellyfin"; mount = "/config"; } ];
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.b2.enable {
      systemd.services.backup-b2 = {
        description = "Daily encrypted Backblaze B2 sync";
        path = with pkgs; [ rclone coreutils ];
        wants = [ "openbao-agent.service" ];
        after = [ "openbao-agent.service" ];
        unitConfig = notifyHooks // {
          RequiresMountsFor = cfg.nasRoot;
        };
        serviceConfig = {
          Type = "oneshot";
          User = "root";
        };
        script = rcloneSweepScript {
          target = "B2";
          dest = "b2crypt:";
          paths = cfg.b2.paths;
          credsBlock = ''
            export RCLONE_CONFIG_B2_TYPE=b2
            RCLONE_CONFIG_B2_ACCOUNT=$(cat ${lib.escapeShellArg "${cfg.b2.secretsDir}/b2-account"})
            RCLONE_CONFIG_B2_KEY=$(cat ${lib.escapeShellArg "${cfg.b2.secretsDir}/b2-key"})
            export RCLONE_CONFIG_B2_ACCOUNT RCLONE_CONFIG_B2_KEY

            export RCLONE_CONFIG_B2CRYPT_TYPE=crypt
            export RCLONE_CONFIG_B2CRYPT_REMOTE=${lib.escapeShellArg cfg.b2.cryptRemote}
            RCLONE_CONFIG_B2CRYPT_PASSWORD=$(cat ${lib.escapeShellArg "${cfg.b2.secretsDir}/b2crypt-pw"})
            export RCLONE_CONFIG_B2CRYPT_PASSWORD

            # Salt (password2) is optional. Only export if openbao-agent has
            # templated a real value — a stale file containing the literal
            # "<no value>" sentinel (consul-template's output for a missing
            # field) is rejected so rclone falls back to its default salt.
            pw2=$(cat ${lib.escapeShellArg "${cfg.b2.secretsDir}/b2crypt-pw2"} 2>/dev/null) || pw2=""
            if [[ -n "$pw2" && "$pw2" != "<no value>" ]]; then
              export RCLONE_CONFIG_B2CRYPT_PASSWORD2="$pw2"
            fi
          '';
        };
      };

      systemd.timers.backup-b2 = {
        description = "Daily encrypted Backblaze B2 sync timer";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.b2.onCalendar;
          Persistent = true;
        };
      };
    })

    (lib.mkIf cfg.local.enable {
      systemd.services.backup-local = {
        description = "Daily local backup sync to USB drive";
        path = with pkgs; [ rclone coreutils util-linux ];
        unitConfig = notifyHooks // {
          RequiresMountsFor = "${cfg.nasRoot} ${cfg.local.destination}";
        };
        serviceConfig = {
          Type = "oneshot";
          User = "root";
        };
        script = rcloneSweepScript {
          target = "LOCAL";
          dest = cfg.local.destination;
          paths = cfg.local.paths;
          preflightExtra = ''
            if ! mountpoint -q "$DEST"; then
              echo "ERROR: $DEST is not mounted — refusing to write to root fs"
              exit 1
            fi
          '';
        };
      };

      systemd.timers.backup-local = {
        description = "Daily local backup sync timer";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.local.onCalendar;
          Persistent = true;
        };
      };
    })

    (lib.mkIf cfg.configs.enable {
      systemd.services.backup-configs = {
        description = "Daily snapshot of container named volumes to NAS";
        path = with pkgs; [ docker rsync coreutils util-linux gnused ];
        wants = [ "docker.service" ];
        after = [ "docker.service" ];
        unitConfig = notifyHooks // {
          RequiresMountsFor = cfg.configs.destination;
        };
        serviceConfig = {
          Type = "oneshot";
          User = "root";
        };
        script = ''
          set -euo pipefail

          START_TIME=$(date +%s)
          COMPOSE_FILE=${lib.escapeShellArg cfg.configs.composeFile}
          DEST_ROOT=${lib.escapeShellArg cfg.configs.destination}

          ${shellPathArray "SERVICES"
              (map (s: "${s.name}:${s.mount}") cfg.configs.services)}

          # Pre-flight
          [[ -f "$COMPOSE_FILE" ]] || { echo "ERROR: compose file missing: $COMPOSE_FILE"; exit 1; }
          mountpoint -q "$DEST_ROOT" || { echo "ERROR: $DEST_ROOT not a mountpoint"; exit 1; }
          touch "$DEST_ROOT/.backup-configs-write-test" 2>/dev/null \
            || { echo "ERROR: $DEST_ROOT not writable"; exit 1; }
          rm -f "$DEST_ROOT/.backup-configs-write-test"

          SUCCEEDED=()
          FAILED=()

          echo "Starting config backup — ''${#SERVICES[@]} service(s)"

          for entry in "''${SERVICES[@]}"; do
            svc="''${entry%%:*}"
            mount_dest="''${entry##*:}"
            dest="$DEST_ROOT/$svc"

            echo "---"
            echo "Service: $svc (mount: $mount_dest)"

            cid=$(docker compose -f "$COMPOSE_FILE" ps -q "$svc" 2>/dev/null || true)
            if [[ -z "$cid" ]]; then
              echo "  ERROR: no running container for service $svc"
              FAILED+=("$svc (not running)")
              continue
            fi

            vol=$(docker inspect "$cid" --format \
              "{{range .Mounts}}{{if and (eq .Type \"volume\") (eq .Destination \"$mount_dest\")}}{{.Name}}{{end}}{{end}}")
            if [[ -z "$vol" ]]; then
              echo "  ERROR: no named volume mounted at $mount_dest in $svc"
              FAILED+=("$svc (volume lookup failed)")
              continue
            fi

            voldir=$(docker volume inspect "$vol" --format '{{.Mountpoint}}')
            echo "  Resolved volume: $vol at $voldir"

            mkdir -p "$dest"

            echo "  Stopping $svc..."
            if ! docker compose -f "$COMPOSE_FILE" stop "$svc"; then
              echo "  ERROR: failed to stop $svc"
              FAILED+=("$svc (stop failed)")
              continue
            fi

            echo "  Syncing $voldir/ -> $dest/"
            if rsync -aHAX --delete "$voldir/" "$dest/"; then
              echo "  OK: $svc"
              SUCCEEDED+=("$svc")
            else
              echo "  ERROR: rsync failed"
              FAILED+=("$svc (rsync failed)")
            fi

            echo "  Starting $svc..."
            if ! docker compose -f "$COMPOSE_FILE" start "$svc"; then
              echo "  ERROR: failed to start $svc — manual intervention may be required"
              FAILED+=("$svc (restart failed)")
            fi
          done

          DURATION=$(( $(date +%s) - START_TIME ))
          echo "---"
          echo "Config backup complete: ''${#SUCCEEDED[@]}/''${#SERVICES[@]} succeeded (''${DURATION}s)"

          if [[ ''${#FAILED[@]} -gt 0 ]]; then
            echo "Failed:"
            for f in "''${FAILED[@]}"; do echo "  - $f"; done
            exit 1
          fi
        '';
      };

      systemd.timers.backup-configs = {
        description = "Daily container volume snapshot timer";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.configs.onCalendar;
          Persistent = true;
        };
      };
    })
  ];
}
