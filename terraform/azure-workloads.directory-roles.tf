locals {
  workload_directory_roles = flatten([
    for directory_assignment_key, workload_environment in local.workload_environments : [
      for directory_assignment in workload_environment.directory_roles : {
        directory_assignment_key = format("%s-%s", workload_environment.key, directory_assignment)
        name                     = directory_assignment
        workload_environment_key = workload_environment.key
      }
    ]
  ])
}

resource "azuread_directory_role_assignment" "workload" {
  for_each = { for each in local.workload_directory_roles : each.directory_assignment_key => each }

  role_id             = azuread_directory_role.builtin[each.value.name].template_id
  principal_object_id = azuread_service_principal.workload[each.value.workload_environment_key].object_id
}
