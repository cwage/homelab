{ config, lib, pkgs, utils, ... }:

# Polls Redheaded Stranger's Instagram feed (via the anonymous
# web_profile_info endpoint — no login) and pushes new posts to a ntfy.sh
# topic. rhs_specials.py is vendored from cwage's rhs project; it dedups by
# post shortcode in the state dir, so overlapping timer firings never
# double-notify.

let
  cfg = config.homelab.rhs-specials;
  stateDir = "/var/lib/rhs-specials";
in
{
  options.homelab.rhs-specials = {
    enable = lib.mkEnableOption "Redheaded Stranger Instagram-to-ntfy notifications";

    topic = lib.mkOption {
      type = lib.types.str;
      default = "rhs-specials";
      description = "ntfy topic name that new posts are published to.";
    };

    server = lib.mkOption {
      type = lib.types.str;
      default = "https://ntfy.sh";
      description = "ntfy server base URL.";
    };

    days = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1;
      description = ''
        How many calendar days back (restaurant-local time) each run
        considers. 1 = today only; dedup makes a wider window safe.
      '';
    };

    match = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = [ "special" ];
      description = ''
        Only notify when the caption contains one of these strings
        (case-insensitive). Empty list = notify on every post.
      '';
    };

    ignore = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = [ "hiring" ];
      description = "Skip posts whose caption contains any of these strings.";
    };

    onCalendar = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "*-*-* 07..13:00:00" "*-*-* 19:00:00" ];
      description = ''
        systemd OnCalendar expressions, host-local time (America/Chicago).
        The default polls hourly through the morning window where specials
        are posted (observed 07:10–11:54 CDT) plus one evening sweep for
        afternoon non-special posts. Each run is a single Instagram
        request, so keep the total to a handful per day.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.rhs-specials = {
      description = "Push new Redheaded Stranger Instagram posts to ntfy";
      # The script shells out to curl for the Instagram fetch: Instagram
      # 429s python's TLS fingerprint but accepts curl's.
      path = [ pkgs.curl ];
      unitConfig.OnFailure = [ "notify-failure@%n.service" ];
      serviceConfig = {
        Type = "oneshot";
        # DynamicUser already implies ProtectSystem=strict and
        # ProtectHome=read-only (systemd.exec(5)); tighten home to
        # inaccessible since the script has no business there.
        DynamicUser = true;
        StateDirectory = "rhs-specials";
        ProtectHome = true;
        NoNewPrivileges = true;
        PrivateTmp = true;
        ExecStart = utils.escapeSystemdExecArgs ([
          "${pkgs.python3}/bin/python3"
          "${./rhs_specials.py}"
          "--server" cfg.server
          "--topic" cfg.topic
          "--days" (toString cfg.days)
          "--state-file" "${stateDir}/seen_posts.txt"
          "--log-file" "${stateDir}/specials_log.md"
        ]
        ++ lib.concatMap (m: [ "--match" m ]) cfg.match
        ++ lib.concatMap (i: [ "--ignore" i ]) cfg.ignore);
      };
    };

    systemd.timers.rhs-specials = {
      description = "Redheaded Stranger Instagram poll timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.onCalendar;
        # Jitter so the poll doesn't hit Instagram at exactly :00 every
        # hour, which reads as bot traffic.
        RandomizedDelaySec = "5m";
        Persistent = true;
      };
    };
  };
}
