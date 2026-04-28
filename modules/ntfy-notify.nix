{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.ntfy;

  # status: "failure" or "success" — controls priority/title/tags
  mkNotifyScript = status:
    let
      attrs = {
        failure = { priority = "urgent"; verb = "failed"; tag = "x"; };
        success = { priority = "low"; verb = "ok"; tag = "white_check_mark"; };
      };
      a = attrs.${status};
    in pkgs.writeShellScript "ntfy-notify-${status}" ''
      set -u
      unit="''${1:-unknown}"
      topic="${cfg.topic}"
      host="$(${pkgs.nettools}/bin/hostname)"

      body=$(${pkgs.systemd}/bin/journalctl -u "$unit" -n 20 --no-pager 2>&1 \
        | ${pkgs.coreutils}/bin/tr -d '[:cntrl:]' \
        | ${pkgs.coreutils}/bin/head -c 4000 \
        || ${pkgs.coreutils}/bin/echo "(no journal output)")

      ${pkgs.curl}/bin/curl -sf -o /dev/null \
        -H "Priority: ${a.priority}" \
        -H "Title: Job ${a.verb} on $host: $unit" \
        -H "Tags: ${a.tag},$host" \
        -d "$body" \
        "$topic" || true
    '';

  mkNotifyService = status: {
    description = "ntfy.sh ${status} notification for %i";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${mkNotifyScript status} %i";
      ProtectSystem = "strict";
      ProtectHome = true;
      NoNewPrivileges = true;
      PrivateTmp = true;
    };
  };
in
{
  options.homelab.ntfy = {
    enable = lib.mkEnableOption "ntfy.sh notifications for systemd units";

    topic = lib.mkOption {
      type = lib.types.str;
      example = "https://ntfy.sh/cwage-homelab-backup";
      description = ''
        Full URL to the ntfy.sh topic that notifications post to.
        Treated as low-sensitivity: leak risk is unsolicited messages on the
        topic, not data exposure. Rotate by changing this value.
      '';
    };
  };

  # Defines two systemd template units. Wire either or both onto a unit:
  #
  #   systemd.services.foo.unitConfig = {
  #     OnFailure = [ "notify-failure@%n.service" ];
  #     OnSuccess = [ "notify-success@%n.service" ];
  #   };
  #
  # `%n` in OnFailure/OnSuccess expands to the failing/finishing unit's full
  # name, which becomes `%i` inside the template — used as the journalctl -u
  # target and notification title.
  config = lib.mkIf cfg.enable {
    systemd.services."notify-failure@" = mkNotifyService "failure";
    systemd.services."notify-success@" = mkNotifyService "success";
  };
}
