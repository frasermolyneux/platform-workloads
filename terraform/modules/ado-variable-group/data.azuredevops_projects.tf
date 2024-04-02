data "azuredevops_project" "project" {
  for_each = { for each in var.azuredevops_projects : each.name => each }

  name = each.value.name
}
