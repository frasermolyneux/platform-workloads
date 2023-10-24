data "azurerm_subscription" "subscriptions" {
  for_each = { for each in var.subscriptions : each.name => each }

  subscription_id = each.value.subscription_id
}
