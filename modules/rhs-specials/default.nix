{ config, lib, pkgs, utils, ... }:

# Two Redheaded Stranger watchers pushing to the same ntfy.sh topic, both
# vendored from cwage's rhs project:
#   - rhs-specials: polls their Instagram feed (anonymous web_profile_info
#     endpoint, no login) for new posts; dedups by post shortcode.
#   - rhs-toast-specials (toast.enable): polls their Toast ordering page via
#     FlareSolverr for the "Specials" menu group and notifies when an item
#     flips out-of-stock -> in-stock — the POS ground truth, catching
#     specials that never get an Instagram post.

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

    toast = {
      enable = lib.mkEnableOption "Toast ordering-menu specials watcher";

      solverUrl = lib.mkOption {
        type = lib.types.str;
        default = "http://127.0.0.1:8191/v1";
        description = ''
          FlareSolverr endpoint used to fetch the Cloudflare-protected Toast
          page (the flaresolverr service in the containers stack compose).
        '';
      };

      onCalendar = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "*-*-* 07..21:00:00" ];
        description = ''
          systemd OnCalendar expressions, host-local time. Stock flips
          follow the kitchen, not a posting schedule: they're open until
          22:00 nightly, so the default covers pre-open prep (weekends open
          at 08:00) through an hour before close, hourly. Each run is one
          headless-browser page load against Toast. Revisit against
          toast_log.md once real flip times accumulate.
        '';
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
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
    })

    (lib.mkIf cfg.toast.enable {
    systemd.services.rhs-toast-specials = {
      description = "Watch the Redheaded Stranger Toast menu for specials coming in stock";
      # The flaresolverr container is compose-managed, so there's no unit to
      # depend on — ordering after docker.service is the best we can do; a
      # run that beats the container up just fails and pings OnFailure.
      after = [ "docker.service" ];
      unitConfig.OnFailure = [ "notify-failure@%n.service" ];
      serviceConfig = {
        Type = "oneshot";
        DynamicUser = true;
        StateDirectory = "rhs-toast-specials";
        ProtectHome = true;
        NoNewPrivileges = true;
        PrivateTmp = true;
        ExecStart = utils.escapeSystemdExecArgs [
          "${pkgs.python3}/bin/python3"
          "${./toast_specials.py}"
          "--solver-url" cfg.toast.solverUrl
          "--server" cfg.server
          "--topic" cfg.topic
          "--state-file" "/var/lib/rhs-toast-specials/toast_state.json"
          "--log-file" "/var/lib/rhs-toast-specials/toast_log.md"
        ];
      };
    };

    systemd.timers.rhs-toast-specials = {
      description = "Redheaded Stranger Toast menu poll timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.toast.onCalendar;
        RandomizedDelaySec = "5m";
        Persistent = true;
      };
    };
    })
  ];
}
