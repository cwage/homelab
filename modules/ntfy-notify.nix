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
      topic=${lib.escapeShellArg cfg.topic}
      host="$(${pkgs.nettools}/bin/hostname)"

      # Capture journal first so we can detect journalctl failures explicitly,
      # then strip control chars (preserving \n and \t for readability) and
      # cap to 4KB.
      body="$(${pkgs.systemd}/bin/journalctl -u "$unit" -n 20 --no-pager 2>&1)" \
        || body="(no journal output)"
      body="$(${pkgs.coreutils}/bin/printf '%s' "$body" \
        | ${pkgs.coreutils}/bin/tr -d '\000-\010\013-\037\177' \
        | ${pkgs.coreutils}/bin/head -c 4000)"

      # --data-raw avoids curl's @filename special-case for payloads that
      # might start with @ (defense in depth — journal output is unlikely
      # to start that way, but cheap to prevent).
      ${pkgs.curl}/bin/curl -sf -o /dev/null \
        -H "Priority: ${a.priority}" \
        -H "Title: Job ${a.verb} on $host: $unit" \
        -H "Tags: ${a.tag},$host" \
        --data-raw "$body" \
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
        Notifications include the last journal lines from the triggering
        unit, so anyone who knows or guesses this URL can read those logs.
        Pick a hard-to-guess topic name and rotate this value if it leaks.
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
