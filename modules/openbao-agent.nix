{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.openbao-agent;

  # Generate agent config HCL from module options
  # Collect unique parent directories of all secret destinations
  secretDirs = lib.unique (lib.mapAttrsToList
    (_: secret: builtins.dirOf secret.destination)
    cfg.secrets);

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
      default = true;
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
    ] ++ map (dir: "d ${dir} 0750 root root -") secretDirs;

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
        ReadWritePaths = [ "/run/openbao-agent" ] ++ secretDirs;
        ProtectHome = true;
        NoNewPrivileges = true;
      };
    };
  };
}
