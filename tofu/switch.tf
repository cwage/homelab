# switch1 — MikroTik CRS310-8G+2S+IN (RouterOS v7)
#
# Basic scaffolding for managing the switch via the terraform-routeros provider.
# This is intentionally minimal: it wires up the provider + credentials and
# manages identity only. Bridge / VLAN / port config comes in a later phase
# (see the abandoned PoC on the switch-vlan-sketch branch for the shape of it).
#
# PREREQUISITES before this can `apply` (none of which exist yet):
#   1. Switch booted on RouterOS, reachable at var.switch_mgmt_ip (10.10.15.7).
#   2. REST API reachable — enable the www-ssl service with a certificate on the
#      switch (/ip service + /certificate), or plain www for http.
#   3. Credentials stored in OpenBao at kv/infra/switch1 (username/password).
#      Create that secret yourself; never commit switch creds.
#
# The routeros provider is declared in main.tf required_providers.

variable "switch_mgmt_ip" {
  description = "Management IP of switch1 (CRS310) on the infra LAN"
  type        = string
  default     = "10.10.15.7"
}

data "vault_kv_secret_v2" "switch1" {
  mount = "kv"
  name  = "infra/switch1"
}

provider "routeros" {
  hosturl  = "https://${var.switch_mgmt_ip}"
  username = data.vault_kv_secret_v2.switch1.data["username"]
  password = data.vault_kv_secret_v2.switch1.data["password"]
  insecure = true # self-signed cert on the switch mgmt interface
}

# First managed resource — sets the device hostname. Proves the provider /
# REST API path works end to end before we layer on bridge + VLAN config.
resource "routeros_system_identity" "switch1" {
  name = "switch1"
}

# --- Deferred to a later phase (kept out on purpose) ---
# routeros_interface_bridge        — the L2 bridge
# routeros_interface_bridge_port   — per-port PVIDs
# routeros_interface_bridge_vlan   — the VLAN table / isolation
# Management IP itself is set statically on the switch (10.10.15.7), not here,
# to avoid locking ourselves out on apply.
