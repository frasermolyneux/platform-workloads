resource "azuread_administrative_unit" "workload" {
  for_each = { for environment in local.workload_environments : environment.key => environment }

  display_name = format("au-%s-%s", lower(each.value.workload_name), lower(each.value.environment_tag))
  description  = format("Administrative unit for workload %s (%s)", each.value.workload_name, each.value.environment_name)
}
