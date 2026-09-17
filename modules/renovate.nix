{ config, lib, pkgs, ... }:

# Self-hosted Renovate (nixpkgs services.renovate) that opens dependency
# update PRs against the homelab repo: flake.lock inputs, the docker-compose
# image pins under hosts/containers/stacks and lego, and the GitHub Actions
# pins. What it updates and how PRs are shaped lives in renovate.json in the
# repo; this module only decides where it runs, how often, and how it
# authenticates.
#
# Self-hosted rather than the Mend app so the same unit carries over to a
# Forgejo remote later: swap platform/endpoint below, nothing else changes.
#
# The token is a fine-grained GitHub PAT scoped to the one repo, delivered
# by openbao-agent to `tokenFile` and handed to renovate via systemd
# LoadCredential (never on the command line or in the unit's environment
# block). PRs it opens trigger the checks workflow like any other PR.

let
  cfg = config.homelab.renovate;
in
{
  options.homelab.renovate = {
    enable = lib.mkEnableOption "self-hosted Renovate runs against the homelab repo";

    repository = lib.mkOption {
      type = lib.types.str;
      default = "cwage/homelab";
      description = "Repository (owner/name) Renovate manages.";
    };

    platform = lib.mkOption {
      type = lib.types.str;
      default = "github";
      example = "gitea";
      description = "Renovate platform. Forgejo uses the gitea platform.";
    };

    endpoint = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "https://git.example.net/api/v1";
      description = "API endpoint for non-github platforms; null for github.com.";
    };

    tokenFile = lib.mkOption {
      type = lib.types.path;
      default = "/etc/secrets/renovate/token";
      description = "File containing the platform API token (RENOVATE_TOKEN).";
    };

    schedule = lib.mkOption {
      type = lib.types.str;
      default = "Mon *-*-* 06:00:00";
      description = "systemd calendar expression for when Renovate runs.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.renovate = {
      enable = true;
      schedule = cfg.schedule;
      credentials.RENOVATE_TOKEN = cfg.tokenFile;
      # nix for the flake.lock manager; git is already on the unit path.
      runtimePackages = [ pkgs.nix ];
      settings = {
        platform = cfg.platform;
        repositories = [ cfg.repository ];
        # renovate.json is committed, so never open an onboarding PR and
        # don't wait for one before doing real work.
        onboarding = false;
        requireConfig = "optional";
        # Rate-limit safety: one repo, one run a week, no need for more.
        prConcurrentLimit = 10;
        # Keep the clone between runs so a weekly run doesn't re-fetch
        # the whole repo (baseDir/cacheDir are set by the nixpkgs module).
        persistRepoData = true;
        # Renovate's nix manager shells out to `nix flake lock`; child processes
        # only see env vars listed here, so pass the flakes switch through.
        customEnvVariables.NIX_CONFIG = "experimental-features = nix-command flakes";
      } // lib.optionalAttrs (cfg.endpoint != null) { endpoint = cfg.endpoint; };
      environment = {
        LOG_LEVEL = "info";
      };
    };

    systemd.services.renovate = {
      # The token is rendered by openbao-agent; order after it so a
      # Persistent timer catching up at boot doesn't race the render. The
      # path condition is the backstop for the agent being unable to log in
      # at all, in which case a clear skip beats a confusing failure.
      after = [ "openbao-agent.service" ];
      wants = [ "openbao-agent.service" ];
      unitConfig = {
        ConditionPathExists = cfg.tokenFile;
        OnFailure = [ "notify-failure@%n.service" ];
      };
      # RandomizedDelaySec isn't exposed by services.renovate.schedule.
    };
    systemd.timers.renovate.timerConfig = {
      Persistent = true;
      RandomizedDelaySec = "30m";
    };
  };
}
