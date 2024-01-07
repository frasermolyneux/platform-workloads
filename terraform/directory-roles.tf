locals {
  directory_roles = [
    "Directory Readers",
    "Directory Writers",
    "Cloud application administrator",
    "Managed Identity Operator"
  ]
}

resource "azuread_directory_role" "builtin" {
  for_each = toset(local.directory_roles)

  display_name = each.value
}
