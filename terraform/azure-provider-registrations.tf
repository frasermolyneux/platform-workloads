locals {
  provider_registrations = flatten([
    for sub_key, sub in var.subscriptions : [
      for provider in var.resource_providers : {
        key             = "${sub.name}-${provider}"
        subscription_id = sub.subscription_id
        provider_name   = provider
      }
    ]
  ])
}

resource "azapi_resource_action" "provider_registration" {
  for_each = { for reg in local.provider_registrations : reg.key => reg }

  type        = "Microsoft.Resources/subscriptions/providers@2024-03-01"
  resource_id = "/subscriptions/${each.value.subscription_id}/providers/${each.value.provider_name}"
  action      = "register"
  method      = "POST"
}
