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

# NixOS hosts need read access to user password hashes (and future secrets)
NIXOS_POLICY_NAME="nixos-host"
NIXOS_POLICY='
path "kv/data/infra/users/*" {
  capabilities = ["read"]
}
path "kv/metadata/infra/users/*" {
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

    echo "Creating AppRole '$name' bound to $ip/32..."

    bao write "auth/approle/role/$name" \
        bind_secret_id=false \
        secret_id_bound_cidrs="" \
        token_bound_cidrs="${ip}/32" \
        token_policies="$NIXOS_POLICY_NAME" \
        token_ttl=1h \
        token_max_ttl=4h \
        token_period=1h

    role_id=$(bao read -field=role_id "auth/approle/role/$name/role-id")

    echo ""
    echo "Role '$name' created."
    echo "  role_id: $role_id"
    echo "  bound_cidr: ${ip}/32"
    echo "  policy: $NIXOS_POLICY_NAME"
    echo ""
    echo "Write this role_id to the host:"
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
