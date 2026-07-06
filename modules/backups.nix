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

      # Source MUST be an active mountpoint, not just an extant directory.
      # rclone sync --delete against an empty stale mountpoint dir would
      # wipe the destination — fail this path closed instead.
      if ! mountpoint -q "$src"; then
        echo "ERROR: $src is not a mountpoint — refusing to sync (would delete destination)"
        FAILED+=("$path (source not mounted)")
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

  # Env-var rclone config for the b2 + b2crypt remotes, shared by the nightly
  # sweep and the verify jobs.
  b2CredsBlock = ''
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

  notifyHooks = {
    OnFailure = [ "notify-failure@%n.service" ];
    OnSuccess = [ "notify-success@%n.service" ];
  };

  # Build a space-separated RequiresMountsFor= value: each entry is resolved
  # by systemd to its containing mount unit, so the service won't start until
  # those NFS shares are actually mounted (not just their parent directory
  # existing). Pairs with the in-script `mountpoint -q` check for cases where
  # systemd thinks a mount is up but it has gone stale mid-run.
  mkMountReqs = paths: lib.concatStringsSep " "
    (map (p: "${cfg.nasRoot}/${p}") paths);
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

    verify = {
      enable = lib.mkEnableOption "Monthly restore verification of the b2/local backups";

      minAge = lib.mkOption {
        type = lib.types.str;
        default = "48h";
        description = ''
          rclone --min-age filter applied when selecting files to verify.
          Files modified more recently than this are skipped, so files that
          changed after the last nightly sync don't produce false mismatches.
        '';
      };

      cryptcheckPaths = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        defaultText = lib.literalExpression "config.homelab.backups.b2.paths";
        description = ''
          Shares to hash-verify against B2 with rclone cryptcheck. Defaults to
          all b2 paths. cryptcheck reads and re-encrypts every source byte to
          compare hashes, so trimming multi-TB shares (e.g. Media) out of this
          list keeps the monthly run short at the cost of hash coverage there —
          the sample-restore job still covers retrievability for all paths.
        '';
      };

      cryptcheckOnCalendar = lib.mkOption {
        type = lib.types.str;
        default = "*-*-01 05:00:00";
        description = "systemd OnCalendar expression for the B2 cryptcheck timer.";
      };

      sampleB2OnCalendar = lib.mkOption {
        type = lib.types.str;
        default = "*-*-01 06:30:00";
        description = "systemd OnCalendar expression for the B2 sample-restore timer.";
      };

      sampleLocalOnCalendar = lib.mkOption {
        type = lib.types.str;
        default = "*-*-01 07:00:00";
        description = "systemd OnCalendar expression for the local sample-restore timer.";
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
    { homelab.backups.verify.cryptcheckPaths = lib.mkDefault cfg.b2.paths; }

    (lib.mkIf (cfg.verify.enable && cfg.b2.enable) {
      systemd.services.verify-b2-cryptcheck = {
        description = "Monthly B2 backup integrity verification (rclone cryptcheck)";
        path = with pkgs; [ rclone coreutils util-linux ];
        wants = [ "openbao-agent.service" ];
        after = [ "openbao-agent.service" ];
        unitConfig = notifyHooks // {
          RequiresMountsFor = mkMountReqs cfg.verify.cryptcheckPaths;
        };
        serviceConfig = {
          Type = "oneshot";
          User = "root";
        };
        script = ''
          set -euo pipefail

          START_TIME=$(date +%s)
          NAS_ROOT=${lib.escapeShellArg cfg.nasRoot}
          MIN_AGE=${lib.escapeShellArg cfg.verify.minAge}
          ${shellPathArray "PATHS" cfg.verify.cryptcheckPaths}

          ${b2CredsBlock}

          ${rcloneFlagsArray}

          FAILED=()
          SUCCEEDED=()

          echo "Starting B2 cryptcheck — ''${#PATHS[@]} path(s)"

          for path in "''${PATHS[@]}"; do
            src="$NAS_ROOT/$path"

            if ! mountpoint -q "$src"; then
              echo "ERROR: $src is not a mountpoint — cannot verify against a stale mount"
              FAILED+=("$path (source not mounted)")
              continue
            fi

            echo "Checking: $src vs b2crypt:$path"
            # --one-way: files present only on the remote (deleted locally
            # since the last sync) are not errors. --min-age skips files the
            # nightly sync may not have uploaded yet.
            if rclone cryptcheck "$src" "b2crypt:$path" --one-way --min-age "$MIN_AGE" "''${RCLONE_FLAGS[@]}"; then
              echo "OK: $path"
              SUCCEEDED+=("$path")
            else
              echo "FAILED: $path"
              FAILED+=("$path")
            fi
          done

          DURATION=$(( $(date +%s) - START_TIME ))
          echo "---"
          echo "Cryptcheck complete: ''${#SUCCEEDED[@]} ok, ''${#FAILED[@]} failed (''${DURATION}s)"

          if [[ ''${#FAILED[@]} -gt 0 ]]; then
            echo "Failed paths:"
            for p in "''${FAILED[@]}"; do echo "  - $p"; done
            exit 1
          fi
        '';
      };

      systemd.timers.verify-b2-cryptcheck = {
        description = "Monthly B2 cryptcheck timer";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.verify.cryptcheckOnCalendar;
          Persistent = true;
        };
      };

      systemd.services.verify-b2-sample = {
        description = "Monthly B2 sample-restore verification";
        path = with pkgs; [ rclone coreutils diffutils util-linux ];
        wants = [ "openbao-agent.service" ];
        after = [ "openbao-agent.service" ];
        unitConfig = notifyHooks // {
          RequiresMountsFor = mkMountReqs cfg.b2.paths;
        };
        serviceConfig = {
          Type = "oneshot";
          User = "root";
        };
        script = ''
          set -euo pipefail

          START_TIME=$(date +%s)
          NAS_ROOT=${lib.escapeShellArg cfg.nasRoot}
          MIN_AGE=${lib.escapeShellArg cfg.verify.minAge}
          ${shellPathArray "PATHS" cfg.b2.paths}

          ${b2CredsBlock}

          ${rcloneFlagsArray}

          WORKDIR=$(mktemp -d)
          trap 'rm -rf "$WORKDIR"' EXIT

          FAILED=()
          SUCCEEDED=()
          SKIPPED=()

          echo "Starting B2 sample restore — ''${#PATHS[@]} path(s)"

          for path in "''${PATHS[@]}"; do
            src="$NAS_ROOT/$path"

            if ! mountpoint -q "$src"; then
              echo "ERROR: $src is not a mountpoint — cannot pick a sample"
              FAILED+=("$path (source not mounted)")
              continue
            fi

            # Random file per run (a fixed sample could be the one healthy
            # object). Listing the *source* with the same excludes as the sync
            # means we only ever pick files the backup claims to contain.
            # Listing failure is a failure, not a skip — only an empty
            # (successful) listing means there's nothing to sample.
            if ! rclone lsf --recursive --files-only --min-age "$MIN_AGE" \
                "''${RCLONE_FLAGS[@]}" "$src" > "$WORKDIR/listing"; then
              echo "FAILED: $path (source listing failed)"
              FAILED+=("$path (source listing failed)")
              continue
            fi

            sample=$(shuf -n 1 "$WORKDIR/listing")
            if [[ -z "$sample" ]]; then
              echo "SKIP: $path (no files older than $MIN_AGE)"
              SKIPPED+=("$path")
              continue
            fi

            echo "Sample: $path/$sample"
            restored="$WORKDIR/sample"
            rm -f "$restored"

            # No RCLONE_FLAGS here: rclone rejects filters (--exclude) on a
            # single-file copyto, and the sample was already chosen from a
            # filtered listing.
            if ! rclone copyto "b2crypt:$path/$sample" "$restored" --log-level INFO; then
              echo "FAILED: $path (download failed: $sample)"
              FAILED+=("$path (download failed: $sample)")
              continue
            fi

            # cmp: 0 = identical, 1 = differ, >1 = couldn't compare — don't
            # report a tooling error as a corrupted backup.
            rc=0
            cmp -s "$src/$sample" "$restored" || rc=$?
            if [[ $rc -eq 0 ]]; then
              echo "OK: $path ($sample)"
              SUCCEEDED+=("$path")
            elif [[ $rc -eq 1 ]]; then
              echo "FAILED: $path (content mismatch: $sample)"
              FAILED+=("$path (content mismatch: $sample)")
            else
              echo "FAILED: $path (compare error rc=$rc: $sample)"
              FAILED+=("$path (compare error: $sample)")
            fi
          done

          DURATION=$(( $(date +%s) - START_TIME ))
          echo "---"
          echo "Sample restore complete: ''${#SUCCEEDED[@]} ok, ''${#FAILED[@]} failed, ''${#SKIPPED[@]} skipped (''${DURATION}s)"

          if [[ ''${#SKIPPED[@]} -gt 0 ]]; then
            echo "Skipped paths (nothing old enough to sample):"
            for p in "''${SKIPPED[@]}"; do echo "  - $p"; done
          fi

          if [[ ''${#FAILED[@]} -gt 0 ]]; then
            echo "Failed paths:"
            for p in "''${FAILED[@]}"; do echo "  - $p"; done
            exit 1
          fi
        '';
      };

      systemd.timers.verify-b2-sample = {
        description = "Monthly B2 sample-restore timer";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.verify.sampleB2OnCalendar;
          Persistent = true;
        };
      };
    })

    (lib.mkIf (cfg.verify.enable && cfg.local.enable) {
      systemd.services.verify-local-sample = {
        description = "Monthly local (USB) sample-restore verification";
        path = with pkgs; [ rclone coreutils diffutils util-linux ];
        unitConfig = notifyHooks // {
          RequiresMountsFor = "${cfg.local.destination} ${mkMountReqs cfg.local.paths}";
        };
        serviceConfig = {
          Type = "oneshot";
          User = "root";
        };
        script = ''
          set -euo pipefail

          START_TIME=$(date +%s)
          NAS_ROOT=${lib.escapeShellArg cfg.nasRoot}
          DEST=${lib.escapeShellArg cfg.local.destination}
          MIN_AGE=${lib.escapeShellArg cfg.verify.minAge}
          ${shellPathArray "PATHS" cfg.local.paths}

          ${rcloneFlagsArray}

          if ! mountpoint -q "$DEST"; then
            echo "ERROR: $DEST is not mounted — nothing to verify"
            exit 1
          fi

          WORKDIR=$(mktemp -d)
          trap 'rm -rf "$WORKDIR"' EXIT

          FAILED=()
          SUCCEEDED=()
          SKIPPED=()

          echo "Starting local sample verification — ''${#PATHS[@]} path(s)"

          for path in "''${PATHS[@]}"; do
            src="$NAS_ROOT/$path"

            if ! mountpoint -q "$src"; then
              echo "ERROR: $src is not a mountpoint — cannot pick a sample"
              FAILED+=("$path (source not mounted)")
              continue
            fi

            # Listing failure is a failure, not a skip — only an empty
            # (successful) listing means there's nothing to sample.
            if ! rclone lsf --recursive --files-only --min-age "$MIN_AGE" \
                "''${RCLONE_FLAGS[@]}" "$src" > "$WORKDIR/listing"; then
              echo "FAILED: $path (source listing failed)"
              FAILED+=("$path (source listing failed)")
              continue
            fi

            sample=$(shuf -n 1 "$WORKDIR/listing")
            if [[ -z "$sample" ]]; then
              echo "SKIP: $path (no files older than $MIN_AGE)"
              SKIPPED+=("$path")
              continue
            fi

            echo "Sample: $path/$sample"
            # cmp: 0 = identical, 1 = differ, >1 = missing/unreadable — keep
            # "backup content wrong" distinct from "couldn't compare".
            rc=0
            cmp -s "$src/$sample" "$DEST/$path/$sample" || rc=$?
            if [[ $rc -eq 0 ]]; then
              echo "OK: $path ($sample)"
              SUCCEEDED+=("$path")
            elif [[ $rc -eq 1 ]]; then
              echo "FAILED: $path (content differs: $sample)"
              FAILED+=("$path (content differs: $sample)")
            else
              echo "FAILED: $path (missing or unreadable rc=$rc: $sample)"
              FAILED+=("$path (missing or unreadable: $sample)")
            fi
          done

          DURATION=$(( $(date +%s) - START_TIME ))
          echo "---"
          echo "Local sample verification complete: ''${#SUCCEEDED[@]} ok, ''${#FAILED[@]} failed, ''${#SKIPPED[@]} skipped (''${DURATION}s)"

          if [[ ''${#SKIPPED[@]} -gt 0 ]]; then
            echo "Skipped paths (nothing old enough to sample):"
            for p in "''${SKIPPED[@]}"; do echo "  - $p"; done
          fi

          if [[ ''${#FAILED[@]} -gt 0 ]]; then
            echo "Failed paths:"
            for p in "''${FAILED[@]}"; do echo "  - $p"; done
            exit 1
          fi
        '';
      };

      systemd.timers.verify-local-sample = {
        description = "Monthly local sample-restore timer";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.verify.sampleLocalOnCalendar;
          Persistent = true;
        };
      };
    })

    (lib.mkIf cfg.b2.enable {
      systemd.services.backup-b2 = {
        description = "Daily encrypted Backblaze B2 sync";
        path = with pkgs; [ rclone coreutils util-linux ];
        wants = [ "openbao-agent.service" ];
        after = [ "openbao-agent.service" ];
        unitConfig = notifyHooks // {
          RequiresMountsFor = mkMountReqs cfg.b2.paths;
        };
        serviceConfig = {
          Type = "oneshot";
          User = "root";
        };
        script = rcloneSweepScript {
          target = "B2";
          dest = "b2crypt:";
          paths = cfg.b2.paths;
          credsBlock = b2CredsBlock;
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
          RequiresMountsFor = "${cfg.local.destination} ${mkMountReqs cfg.local.paths}";
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
