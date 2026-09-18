{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.wildcardCertificate;
  enabled = cfg.renewal.enable || cfg.monitor.enable;
  json = pkgs.formats.json { };
  common = {
    domain = "lan.quietlife.net";
    endpoints = [
      { host = "bao.lan.quietlife.net"; port = 8200; }
      { host = "chat.lan.quietlife.net"; port = 443; }
    ];
  };
  renewalConfig = json.generate "wildcard-renewal.json" (common // {
    state_dir = "/var/lib/wildcard-renewal";
    bao_url = config.homelab.openbao-agent.address;
    token_file = "/run/openbao-agent/token";
    cloudflare_token_file = "/etc/secrets/wildcard-renewal/cloudflare-token";
    compose_file = "${../../lego/docker-compose.yml}";
    email = "cwage@quietlife.net";
    renew_days = 30;
    propagation_seconds = 900;
  });
  monitorConfig = json.generate "wildcard-monitor.json" (common // {
    state_dir = "/var/lib/wildcard-monitor";
    topic = config.homelab.ntfy.topic;
  });
  baseService = {
    Type = "oneshot";
    UMask = "0077";
    StateDirectoryMode = "0700";
    ProtectSystem = "strict";
    ProtectHome = true;
    PrivateTmp = true;
    NoNewPrivileges = true;
  };
  mkTimer = calendar: {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = calendar;
      Persistent = true;
      RandomizedDelaySec = "15m";
    };
  };
in
{
  options.homelab.wildcardCertificate = {
    renewal.enable = lib.mkEnableOption "daily LAN wildcard renewal and propagation verification";
    monitor.enable = lib.mkEnableOption "independent live TLS expiry alerts for Bao and Traefik";
  };

  config = lib.mkMerge [
    (lib.mkIf enabled {
      assertions = [{
        assertion = config.homelab.ntfy.enable;
        message = "Wildcard certificate jobs require homelab.ntfy.enable.";
      }];
    })
    (lib.mkIf cfg.renewal.enable {
      assertions = [{
        assertion = config.homelab.openbao-agent.enable && config.virtualisation.docker.enable;
        message = "Wildcard renewal requires OpenBao agent and Docker.";
      }];
      homelab.openbao-agent.secrets.wildcard-cloudflare-token = {
        path = "kv/data/infra/cloudflare";
        field = "api_token";
        destination = "/etc/secrets/wildcard-renewal/cloudflare-token";
      };
      systemd.services.wildcard-renewal = {
        description = "Renew LAN wildcard and verify live certificate propagation";
        after = [ "network-online.target" "docker.service" "openbao-agent.service" ];
        wants = [ "network-online.target" "docker.service" "openbao-agent.service" ];
        path = [ pkgs.docker pkgs.docker-compose pkgs.openssl ];
        environment.SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
        unitConfig.OnFailure = [ "notify-failure@%n.service" ];
        # Missing credentials must FAIL and alert, not silently skip a run.
        serviceConfig = baseService // {
          StateDirectory = "wildcard-renewal";
          TimeoutStartSec = "45m";
          ExecStart = "${pkgs.python3}/bin/python ${./certificate.py} renew ${renewalConfig}";
        };
      };
      systemd.timers.wildcard-renewal = mkTimer "*-*-* 04:00:00 America/Chicago";
    })
    (lib.mkIf cfg.monitor.enable {
      systemd.services.wildcard-monitor = {
        description = "Check live Bao and Traefik TLS independently of renewal";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        environment.SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
        unitConfig.OnFailure = [ "notify-failure@%n.service" ];
        serviceConfig = baseService // {
          DynamicUser = true;
          StateDirectory = "wildcard-monitor";
          TimeoutStartSec = "3m";
          ExecStart = "${pkgs.python3}/bin/python ${./certificate.py} monitor ${monitorConfig}";
        };
      };
      systemd.timers.wildcard-monitor = mkTimer "*-*-* 06:00:00 America/Chicago";
    })
  ];
}
