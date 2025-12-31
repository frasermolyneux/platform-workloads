import {
  to = azapi_resource.workload_resource_group["platform-monitoring-Development-uksouth-rg-platform-monitoring-dev-uksouth"]
  id = format("%s/resourceGroups/%s", data.azurerm_subscription.subscriptions["sub-visualstudio-enterprise"].id, "rg-platform-monitoring-dev-uksouth")
}

import {
  to = azapi_resource.workload_resource_group["platform-monitoring-Production-uksouth-rg-platform-monitoring-prd-uksouth"]
  id = format("%s/resourceGroups/%s", data.azurerm_subscription.subscriptions["sub-platform-management"].id, "rg-platform-monitoring-prd-uksouth")
}
