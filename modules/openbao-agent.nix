{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.openbao-agent;

  # Generate agent config HCL from module options
  # All unique parent directories of secret destinations (used for the agent
  # service's ReadWritePaths, regardless of who creates the dir).
  allSecretDirs = lib.unique (lib.mapAttrsToList
    (_: secret: builtins.dirOf secret.destination)
    cfg.secrets);

  # Subset whose parent dir we should auto-create via tmpfiles. Excludes any
  # dir that's already declared in a host config (manageDestinationDir = false).
  managedSecretDirs = lib.unique (lib.mapAttrsToList
    (_: secret: builtins.dirOf secret.destination)
    (lib.filterAttrs (_: secret: secret.manageDestinationDir) cfg.secrets));

  agentConfig = ''
    vault {
      address = "${cfg.address}"
      ${lib.optionalString cfg.tlsSkipVerify "tls_skip_verify = true"}
    }

    auto_auth {
      method "approle" {
        config = {
          role_id_file_path = "/etc/openbao/role_id"
          ${lib.optionalString (cfg.secretIdFile != null)
            ''secret_id_file_path = "${cfg.secretIdFile}"''}
        }
      }

      sink "file" {
        config = {
          path = "/run/openbao-agent/token"
        }
      }
    }

    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: secret: ''
    template {
      contents = "{{ with secret \"${secret.path}\" }}{{ index .Data.data \"${secret.field}\" }}{{ end }}"
      destination = "${secret.destination}"
      perms = "${secret.permissions}"
      ${lib.optionalString (secret.owner != null) ''user = ${builtins.toJSON secret.owner}''}
      ${lib.optionalString (secret.group != null) ''group = ${builtins.toJSON secret.group}''}
      ${lib.optionalString (secret.command != null) ''command = ${builtins.toJSON secret.command}''}
    }
    '') cfg.secrets)}
  '';
in
{
  options.homelab.openbao-agent = {
    enable = lib.mkEnableOption "OpenBao agent for secrets management";

    address = lib.mkOption {
      type = lib.types.str;
      default = "https://bao.lan.quietlife.net:8200";
      description = "OpenBao server address.";
    };

    tlsSkipVerify = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Skip TLS certificate verification.";
    };

    roleId = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        AppRole role_id for this host. Written to /etc/openbao/role_id.
        Not secret — with CIDR binding, only the bound IP can use it.
        Set to null to manage the file out-of-band (e.g., via Tofu provisioner).
      '';
    };

    secretIdFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Path to secret_id file. Null for CIDR-bound roles (no secret_id needed).";
    };

    secrets = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          path = lib.mkOption {
            type = lib.types.str;
            description = "OpenBao KV v2 secret path (e.g., kv/data/infra/users/cwage).";
          };
          field = lib.mkOption {
            type = lib.types.str;
            description = "Field within the secret to extract.";
          };
          destination = lib.mkOption {
            type = lib.types.str;
            description = "File path to write the secret value to.";
          };
          permissions = lib.mkOption {
            type = lib.types.str;
            default = "0400";
            description = "File permissions for the rendered secret.";
          };
          owner = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = ''
              Owning user for the rendered file. Null leaves it as the agent
              process user (root). Required when the consuming service runs as
              a non-root user that cannot otherwise read the file.
            '';
          };
          group = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = ''
              Owning group for the rendered file. Null leaves it as the agent
              process group (root).
            '';
          };
          command = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = ''
              Command to run after the destination file is rendered (i.e.
              on rotation). The agent runs as root, so this command runs
              as root. Typical: 'systemctl reload <svc>' or
              'docker restart <container>'.

              Multi-file fanout (e.g. cert + key from the same KV path):
              set the command on only ONE secret, the one rendered LAST.
              openbao-agent (consul-template under the hood) renders
              templates sequentially in their HCL declaration order, which
              this module emits in alphabetical order of the cfg.secrets
              attribute name. Naming pair members so that the one carrying
              the command sorts last (e.g. `tls-key` after `tls-cert`)
              guarantees the command fires only after both files are on
              disk, so the consumer never reloads mid-fanout.
            '';
          };
          manageDestinationDir = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = ''
              Whether the module should auto-create the destination's parent
              directory (0750 root:root) via systemd.tmpfiles. Set to false
              when the directory is already declared elsewhere in the host
              config with the ownership/perms the consumer needs (e.g.
              /var/lib/openbao/tls owned by openbao:openbao on bao2). The
              agent's ReadWritePaths still includes the parent dir either
              way, so the agent can write into it.
            '';
          };
        };
      });
      default = {};
      description = "Secrets to fetch and template to files.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.openbao ];

    # Persistent secrets directory (survives reboots so services have
    # secrets available before the agent reconnects on next boot)
    systemd.tmpfiles.rules = [
      "d /etc/openbao 0750 root root -"
      "d /run/openbao-agent 0750 root root -"
    ] ++ map (dir: "d ${dir} 0750 root root -") managedSecretDirs;

    # Write role_id if provided in config (not secret with CIDR binding)
    environment.etc."openbao/role_id" = lib.mkIf (cfg.roleId != null) {
      text = cfg.roleId;
      mode = "0640";
    };

    # Write agent config
    environment.etc."openbao/agent.hcl" = {
      text = agentConfig;
      mode = "0640";
    };

    # openbao-agent systemd service
    systemd.services.openbao-agent = {
      description = "OpenBao Agent";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      # Restart the daemon when its config or bound role_id changes — without
      # this, edits to the secrets list update /etc/openbao/agent.hcl on disk
      # but the running process keeps using its in-memory template list.
      restartTriggers = [ agentConfig ]
        ++ lib.optional (cfg.roleId != null) cfg.roleId;

      # Don't start until role_id exists (written by NixOS activation if
      # roleId is set, or delivered out-of-band by Tofu/cloud-init)
      unitConfig.ConditionPathExists = "/etc/openbao/role_id";

      path = [ pkgs.getent ];

      serviceConfig = {
        ExecStart = "${pkgs.openbao}/bin/bao agent -config=/etc/openbao/agent.hcl";
        Restart = "on-failure";
        RestartSec = "5s";
        # Hardening
        ProtectSystem = "strict";
        ReadWritePaths = [ "/run/openbao-agent" ] ++ allSecretDirs;
        ProtectHome = true;
        NoNewPrivileges = true;
      };
    };
  };
}
