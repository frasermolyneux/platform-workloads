import {
  for_each = var.environment == "prd" ? {
    "portal-environments-Development-uksouth-rg-portal-environments-dev-uksouth" = "/subscriptions/d68448b0-9947-46d7-8771-baa331a3063a/resourceGroups/rg-portal-environments-dev-uksouth"
    "portal-environments-Production-uksouth-rg-portal-environments-prd-uksouth"  = "/subscriptions/32444f38-32f4-409f-889c-8e8aa2b5b4d1/resourceGroups/rg-portal-environments-prd-uksouth"
  } : {}

  to = azapi_resource.workload_resource_group[each.key]
  id = each.value
}
