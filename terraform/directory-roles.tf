locals {
  directory_roles_builtin = [
    "Directory Readers",
    "Directory Writers",
    "Cloud application administrator",
    "Groups Administrator",
    "Application Administrator"
  ]
}

resource "azuread_directory_role" "builtin" {
  for_each = toset(local.directory_roles_builtin)

  display_name = each.value
}

locals {
  directory_role_ids        = { for name, role in azuread_directory_role.builtin : name => role.template_id }
  directory_role_object_ids = { for name, role in azuread_directory_role.builtin : name => role.object_id }
}
