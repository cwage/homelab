#!/usr/bin/env bash
# Runs via make ansible-check, in a disposable container using the deploy image's
# Dockerfile. Collections go into /tmp so local installs cannot mask bad pins.
set -euo pipefail
export PATH="/opt/venv/bin:$PATH"

ansible --version
ansible-galaxy collection install -r requirements.yml -p "$ANSIBLE_COLLECTIONS_PATH"

# Syntax checks do not evaluate lookups or load become plugins. Load their
# documentation explicitly to check resolution and requires_ansible metadata,
# without executing plugins or contacting OpenBao/SSH targets.
check_plugins() {
    local plugin_type=$1
    shift
    # ansible-doc only warns (exit 0) for missing plugins. Check its JSON too.
    ansible-doc --json --type "$plugin_type" "$@" | python -c '
import json
import sys

docs = json.load(sys.stdin)
missing = [name for name in sys.argv[1:] if not docs.get(name)]
if missing:
    sys.exit("Missing plugins: " + ", ".join(missing))
' "$@"
}

check_plugins module ansible.posix.authorized_key ansible.posix.mount
check_plugins become community.general.doas
check_plugins lookup community.hashi_vault.vault_kv2_get

ansible-playbook --syntax-check playbooks/*.yml
