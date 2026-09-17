{ config, lib, pkgs, ... }:

# Weekly "your deployed nixpkgs is getting old" nag, posted via the ntfy
# module (modules/ntfy-notify.nix). Two dates are baked in at build time and
# compared against the clock at run time:
#
#   - the nixpkgs commit date behind this generation (from the flake.lock rev
#     that built it), alerting once it is older than maxAgeDays;
#   - the end-of-life of the nixpkgs release branch this generation tracks,
#     alerting once we're within eolWarnDays of it or past it.
#
# A stale lock is the one thing a Nix host will never tell you about on its
# own: nothing on the box changes until someone bumps flake.lock and
# redeploys, so a 15-month-old system looks perfectly healthy from the inside.
# This is the reminder that it isn't. Deploying a fresh build resets the clock.
#
# Alerting reuses the notify-failure@ template: the check exits non-zero when
# something is stale and its own journal lines (the summary it printed) become
# the notification body. Loud on purpose.

let
  cfg = config.homelab.staleness;
  nixos = config.system.nixos;

  # versionSuffix looks like ".20260915.b67c7a6" when built from a flake:
  # the nixpkgs commit date (YYYYMMDD) then the short rev.
  suffixMatch = builtins.match "\\.([0-9]{8})\\..*" nixos.versionSuffix;
  nixpkgsDate =
    if suffixMatch == null
    then throw "homelab.staleness: cannot parse nixpkgs date from versionSuffix '${nixos.versionSuffix}'"
    else builtins.head suffixMatch;

  # Release branches are cut in May (YY.05) and November (YY.11) and supported
  # for about a month past the next release, so 26.05 is EOL at the end of
  # December 2026 and 26.11 at the end of June 2027.
  relMatch = builtins.match "([0-9]{2})\\.(05|11)" nixos.release;
  eolDate =
    if relMatch == null
    then throw "homelab.staleness: unexpected release string '${nixos.release}'"
    else
      let
        yy = lib.toInt (builtins.elemAt relMatch 0);
        month = builtins.elemAt relMatch 1;
      in
      if month == "05"
      then "20${toString yy}-12-31"
      else "20${toString (yy + 1)}-06-30";

  checkScript = pkgs.writeShellScript "nixos-staleness-check" ''
    set -eu
    PATH=${lib.makeBinPath [ pkgs.coreutils ]}

    now=$(date +%s)
    built=$(date -d ${nixpkgsDate} +%s)
    eol=$(date -d ${eolDate} +%s)
    lock_age=$(( (now - built) / 86400 ))
    eol_in=$(( (eol - now) / 86400 ))

    echo "nixpkgs ${nixos.release} rev ${nixos.revision or "unknown"} dated ${nixpkgsDate}: $lock_age days old (limit ${toString cfg.maxAgeDays})"
    echo "release ${nixos.release} EOL ${eolDate}: $eol_in days away (warn at ${toString cfg.eolWarnDays})"

    stale=0
    if [ "$lock_age" -gt ${toString cfg.maxAgeDays} ]; then
      echo "STALE: bump flake.lock and redeploy this host"
      stale=1
    fi
    if [ "$eol_in" -lt ${toString cfg.eolWarnDays} ]; then
      echo "EOL: move flake.nix to the next nixos-YY.MM branch"
      stale=1
    fi
    exit $stale
  '';
in
{
  options.homelab.staleness = {
    enable = lib.mkEnableOption "weekly ntfy nag when the deployed nixpkgs is old or its release is near EOL";

    maxAgeDays = lib.mkOption {
      type = lib.types.int;
      default = 30;
      description = "Alert when the deployed nixpkgs commit is older than this many days.";
    };

    eolWarnDays = lib.mkOption {
      type = lib.types.int;
      default = 30;
      description = "Alert when the tracked nixpkgs release is within this many days of end-of-life.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = config.homelab.ntfy.enable;
      message = "homelab.staleness needs homelab.ntfy.enable so the nag has somewhere to go.";
    }];

    systemd.services.nixos-staleness-check = {
      description = "Nag when the deployed nixpkgs is stale or near EOL";
      unitConfig.OnFailure = [ "notify-failure@%n.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = checkScript;
        DynamicUser = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateNetwork = true;
      };
    };

    systemd.timers.nixos-staleness-check = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "weekly";
        # Fire on next boot if the host was down for the scheduled run, and
        # spread the hosts out so they don't all post at once.
        Persistent = true;
        RandomizedDelaySec = "4h";
      };
    };
  };
}
