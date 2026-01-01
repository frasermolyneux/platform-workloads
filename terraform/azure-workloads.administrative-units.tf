locals {
  administrative_unit_keys = keys(var.administrative_units)
}

resource "azuread_administrative_unit" "platform" {
  for_each = var.administrative_units

  display_name = coalesce(try(each.value.display_name, null), each.key)
  description  = try(each.value.description, null)
}
