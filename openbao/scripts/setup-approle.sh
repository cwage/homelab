#!/bin/sh
# Setup AppRole auth in OpenBao for NixOS hosts
#
# Runs inside the openbao container via Make targets.
#
# Usage:
#   setup-approle.sh enable                     # one-time: enable AppRole auth
#   setup-approle.sh create-role dns1 10.10.15.15   # create role for a host
#   setup-approle.sh show-role dns1             # show role_id for a host
#   setup-approle.sh list                       # list all roles

set -eu

# NixOS hosts need read access to user password hashes and the LE wildcard
# cert (delivered to bao's TCP listener and to Traefik on containers2 via
# openbao-agent). Containers2's backup secrets at kv/data/backup/* are
# granted by additional policy attachments on that role, not by this base
# policy.
NIXOS_POLICY_NAME="nixos-host"
NIXOS_POLICY='
path "kv/data/infra/users/*" {
  capabilities = ["read"]
}
path "kv/metadata/infra/users/*" {
  capabilities = ["read"]
}
path "kv/data/infra/certs/*" {
  capabilities = ["read"]
}
path "kv/metadata/infra/certs/*" {
  capabilities = ["read"]
}
'

usage() {
    echo "Usage: $0 <command> [args]"
    echo ""
    echo "Commands:"
    echo "  enable                      Enable AppRole auth method (one-time)"
    echo "  create-role <name> <ip>     Create CIDR-bound AppRole for a NixOS host"
    echo "  show-role <name>            Show the role_id for a host"
    echo "  list                        List all AppRole roles"
    exit 1
}

cmd_enable() {
    echo "Enabling AppRole auth method..."
    bao auth enable approle 2>/dev/null || echo "  (already enabled)"

    echo "Writing nixos-host policy..."
    echo "$NIXOS_POLICY" | bao policy write "$NIXOS_POLICY_NAME" -

    echo ""
    echo "AppRole auth enabled with policy '$NIXOS_POLICY_NAME'."
    echo "Next: create a role for each NixOS host with 'make openbao-approle-create-role NAME=dns1 IP=10.10.15.15'"
}

cmd_create_role() {
    name="${1:?Usage: create-role <name> <ip>}"
    ip="${2:?Usage: create-role <name> <ip>}"
    # Optional env vars:
    #   EXTRA_CIDRS:    comma-separated extra CIDRs to add to the binding.
    #                   Used when the agent connects from an additional source
    #                   IP (e.g. bao needs 127.0.0.1/32 because its agent
    #                   talks to its own openbao via loopback).
    #   EXTRA_POLICIES: comma-separated extra policies to add on top of the
    #                   base nixos-host policy and any policies already
    #                   attached out-of-band (e.g. containers2 has
    #                   backup-remote attached). Existing policies are
    #                   ALWAYS preserved on re-run — see the read-then-merge
    #                   logic below.
    extra_cidrs="${EXTRA_CIDRS:-}"
    extra_policies="${EXTRA_POLICIES:-}"

    if [ -n "$extra_cidrs" ]; then
        cidrs="${ip}/32,${extra_cidrs}"
    else
        cidrs="${ip}/32"
    fi

    # Read the role's current token_policies if the role exists, so re-running
    # this command is non-destructive for policies attached out-of-band. Since
    # `bao write` replaces token_policies wholesale, naively writing just
    # NIXOS_POLICY_NAME would silently drop attachments like backup-remote.
    existing=""
    if existing_json=$(bao read -format=json "auth/approle/role/$name" 2>/dev/null); then
        existing=$(echo "$existing_json" | jq -r '.data.token_policies | join(",")')
    fi

    # Merge: existing + base + extras, deduped. tr/sort/paste handles dedup
    # without requiring jq for the merge step.
    merged="$existing,$NIXOS_POLICY_NAME"
    if [ -n "$extra_policies" ]; then
        merged="$merged,$extra_policies"
    fi
    policies=$(echo "$merged" | tr ',' '\n' | sed '/^$/d' | sort -u | paste -sd ',')

    echo "Creating/updating AppRole '$name'..."
    echo "  bound_cidrs:    $cidrs"
    echo "  token_policies: $policies"
    if [ -n "$existing" ] && [ "$existing" != "$NIXOS_POLICY_NAME" ]; then
        echo "    (preserved existing: $existing)"
    fi

    bao write "auth/approle/role/$name" \
        bind_secret_id=false \
        secret_id_bound_cidrs="" \
        token_bound_cidrs="$cidrs" \
        token_policies="$policies" \
        token_ttl=1h \
        token_max_ttl=4h \
        token_period=1h

    role_id=$(bao read -field=role_id "auth/approle/role/$name/role-id")

    echo ""
    echo "Role '$name' written. (Upsert — role_id preserved across re-runs.)"
    echo "  role_id: $role_id"
    echo ""
    echo "If this is a NEW host, write the role_id to the host:"
    echo "  ssh deploy@${name} 'sudo mkdir -p /etc/openbao && echo \"$role_id\" | sudo tee /etc/openbao/role_id'"
}

cmd_show_role() {
    name="${1:?Usage: show-role <name>}"
    bao read -field=role_id "auth/approle/role/$name/role-id"
}

cmd_list() {
    bao list auth/approle/role
}

[ $# -lt 1 ] && usage

case "$1" in
    enable)       cmd_enable ;;
    create-role)  cmd_create_role "${2:-}" "${3:-}" ;;
    show-role)    cmd_show_role "${2:-}" ;;
    list)         cmd_list ;;
    *)            usage ;;
esac
