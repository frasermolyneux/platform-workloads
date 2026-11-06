# Temporary read-only probe; do not merge or apply this configuration.
data "cloudflare_api_token_permission_groups_list" "dynamic_url_redirects_probe" {
  name      = urlencode("Dynamic URL Redirects Write")
  max_items = 2

  lifecycle {
    postcondition {
      condition = try(
        length(self.result) == 1 &&
        self.result[0].name == "Dynamic URL Redirects Write" &&
        contains(self.result[0].scopes, "com.cloudflare.api.account.zone"),
        false
      )
      error_message = "The Dynamic URL Redirects Write lookup must return exactly one exact-name, zone-scoped permission group."
    }
  }
}
