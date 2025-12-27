locals {
  resource_group_name = "rg-platform-workloads-${var.environment}-${var.location}-${var.instance}"
  key_vault_name      = "kv-${random_id.environment_id.hex}-${var.location}"
}
