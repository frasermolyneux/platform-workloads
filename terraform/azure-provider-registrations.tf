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

resource "terraform_data" "provider_registration" {
  for_each = { for reg in local.provider_registrations : reg.key => reg }

  input = {
    subscription_id = each.value.subscription_id
    provider_name   = each.value.provider_name
  }

  provisioner "local-exec" {
    command = "az provider register --namespace ${self.input.provider_name} --subscription ${self.input.subscription_id}"
  }
}
