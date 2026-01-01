locals {
  workload_directory_roles_tenant = flatten([
    for directory_assignment_key, workload_environment in local.workload_environments : [
      for directory_assignment in workload_environment.directory_roles : {
        directory_assignment_key   = format("%s-%s", workload_environment.key, directory_assignment)
        name                       = directory_assignment
        workload_environment_key   = workload_environment.key
        add_deploy_script_identity = workload_environment.add_deploy_script_identity
      }
    ]
  ])

  workload_directory_roles_au = flatten([
    for workload_environment in local.workload_environments : [
      for assignment in workload_environment.administrative_unit_roles : [
        for role in assignment.roles : {
          directory_assignment_key   = format("%s-%s-%s", workload_environment.key, assignment.administrative_unit_key, role)
          name                       = role
          administrative_unit_key    = assignment.administrative_unit_key
          workload_environment_key   = workload_environment.key
          add_deploy_script_identity = workload_environment.add_deploy_script_identity
        }
      ]
      if contains(local.administrative_unit_keys, assignment.administrative_unit_key)
    ]
  ])
}

resource "azuread_directory_role_assignment" "workload" {
  for_each = {
    for each in local.workload_directory_roles_tenant : each.directory_assignment_key => each
  }

  role_id             = local.directory_role_ids[each.value.name]
  principal_object_id = azuread_service_principal.workload[each.value.workload_environment_key].object_id
}

resource "azuread_directory_role_assignment" "workload_deploy_script" {
  for_each = {
    for each in local.workload_directory_roles_tenant : each.directory_assignment_key => each
    if each.add_deploy_script_identity
  }

  role_id             = local.directory_role_ids[each.value.name]
  principal_object_id = azurerm_user_assigned_identity.workload_deploy_script[each.value.workload_environment_key].principal_id
}

resource "azuread_administrative_unit_role_member" "workload" {
  for_each = {
    for each in local.workload_directory_roles_au : each.directory_assignment_key => each
  }

  administrative_unit_object_id = azuread_administrative_unit.platform[each.value.administrative_unit_key].object_id
  role_object_id                = local.directory_role_object_ids[each.value.name]
  member_object_id              = azuread_service_principal.workload[each.value.workload_environment_key].object_id
}

resource "azuread_administrative_unit_role_member" "workload_deploy_script" {
  for_each = {
    for each in local.workload_directory_roles_au : each.directory_assignment_key => each
    if each.add_deploy_script_identity
  }

  administrative_unit_object_id = azuread_administrative_unit.platform[each.value.administrative_unit_key].object_id
  role_object_id                = local.directory_role_object_ids[each.value.name]
  member_object_id              = azurerm_user_assigned_identity.workload_deploy_script[each.value.workload_environment_key].principal_id
}
