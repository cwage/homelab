# switch1 — MikroTik CRS310-8G+2S+IN (RouterOS v7)
#
# Manages the switch via the terraform-routeros provider. Intentionally minimal:
# system identity only. Bridge / VLAN / port config comes in a later phase (see
# the abandoned PoC on the switch-vlan-sketch branch for the shape of it).
#
# For `apply` to reach the switch, the following must hold:
#   1. Switch booted on RouterOS, reachable at var.switch_mgmt_ip (10.10.15.7).
#   2. REST API reachable — the www-ssl service enabled with a certificate on the
#      switch (/ip service + /certificate), or plain www for http.
#   3. Credentials stored in OpenBao at kv/infra/switch1 (username/password).
#      Never commit switch creds.
#
# The routeros provider block lives in main.tf; var.switch_mgmt_ip in variables.tf.

data "vault_kv_secret_v2" "switch1" {
  mount = "kv"
  name  = "infra/switch1"
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
