#!/usr/bin/env bash
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [[ -z "$repo_root" ]]; then
  echo "This script must be run inside a git repository." >&2
  exit 1
fi

hook_src="$repo_root/hooks/pre-commit"
hook_dst="$repo_root/.git/hooks/pre-commit"

if [[ ! -f "$hook_src" ]]; then
  echo "Hook source $hook_src is missing." >&2
  exit 1
fi

mkdir -p "$repo_root/.git/hooks"
install -m 0755 "$hook_src" "$hook_dst"

echo "Installed pre-commit hook to $hook_dst"
