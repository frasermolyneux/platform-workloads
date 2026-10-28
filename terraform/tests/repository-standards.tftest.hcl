run "validate_repository_standards_projection" {
  command = plan

  plan_options {
    target = [terraform_data.repository_standards_contract]
  }

  assert {
    condition     = length(local.repository_standards_variables) == 48
    error_message = "All 48 applicable non-xi repository analysis profiles must receive repository standards."
  }

  assert {
    condition = (
      length(local.repository_standards_catalog) == 48 &&
      jsonencode(sort(keys(local.repository_standards_catalog))) == jsonencode(sort(keys(local.repository_standards_workloads))) &&
      jsonencode(sort(keys(local.repository_standards_catalog))) == jsonencode(sort(keys(local.repository_standards_documents)))
    )
    error_message = "The aggregate catalog must contain exactly the applicable repository standards workload keys."
  }

  assert {
    condition = (
      length([
        for name in keys(local.repository_standards_workloads) : name
        if local.repository_standards_workloads[name].github.visibility == "public"
      ]) == 39 &&
      length([
        for name in keys(local.repository_standards_workloads) : name
        if local.repository_standards_workloads[name].github.visibility == "private"
      ]) == 9
    )
    error_message = "Repository standards applicability must include the expected public and private catalog rows."
  }

  assert {
    condition = (
      jsonencode(local.repository_standards_profiles["actions"]) == jsonencode(["base"]) &&
      jsonencode(local.repository_standards_profiles["platform-workloads"]) == jsonencode([
        "base",
        "cost-optimised",
        "public-endpoints",
        "app-service-standard",
        "central-observability",
      ]) &&
      jsonencode(local.repository_standards_profiles["platform-baremetal"]) == jsonencode([
        "base",
        "cost-optimised",
        "public-endpoints-resource-scoped",
        "app-service-standard",
        "central-observability",
      ]) &&
      jsonencode(local.repository_standards_profiles["platform-sitewatch-func"]) == jsonencode([
        "base",
        "cost-optimised-resource-scoped",
        "public-endpoints",
        "app-service-standard",
        "central-observability",
      ])
    )
    error_message = "Profile selection must be deterministic for base-only, policy-only infrastructure, and private infrastructure repositories."
  }

  assert {
    condition = (
      alltrue([
        for name, profiles in local.repository_standards_profiles :
        contains(["platform-baremetal", "platform-sitewatch-func"], name) ||
        jsonencode(profiles) == jsonencode(local.repository_standards_default_profiles[name])
      ]) &&
      alltrue(values(local.repository_standards_overrides_valid)) &&
      alltrue(values(local.repository_standards_documents_valid)) &&
      jsonencode(local.repository_standards_exceptions["platform-baremetal"]) == "[]" &&
      jsonencode(local.repository_standards_exceptions["platform-sitewatch-func"]) == "[]"
    )
    error_message = "Only the two declared resource-scoped variants may change profile selection; neither control may become a global exception."
  }

  assert {
    condition = (
      jsonencode(local.repository_standards_checkov_exception_allowlist) == jsonencode([
        "CKV_OPENAPI_21",
        "CKV_SECRET_6",
      ]) &&
      local.repository_standards_documents["trip-side-kick"].version == "repository-standards-v1" &&
      local.repository_standards_documents["trip-side-kick"].managedFiles.checkov.version == "checkov-v1" &&
      alltrue([
        for exception in local.repository_standards_documents["trip-side-kick"].managedFiles.checkov.exceptions :
        contains(local.repository_standards_checkov_exception_allowlist, exception.rule) &&
        exception.reason == trimspace(exception.reason) &&
        length(exception.reason) >= 10 &&
        length(exception.reason) <= 600 &&
        !can(regex("[\u0000-\u001F\u007F-\u009F\u2028\u2029\uFFFE\uFFFF]", exception.reason))
      ]) &&
      jsonencode(local.repository_standards_documents["trip-side-kick"].managedFiles.checkov.exceptions) == jsonencode([
        {
          rule   = "CKV_OPENAPI_21"
          reason = "src/MX.TripSideKick.Web/ClientApp/openapi.json is generated from the ASP.NET Core minimal OpenAPI pipeline and consumed by openapi-typescript to produce client types. maxItems is not emitted by the generator and adding it by hand would be overwritten on every regeneration; array bounds are enforced in the API models/validation, not in the schema document."
        }
      ])
    )
    error_message = "The exact Checkov exception allowlist and Trip Side Kick generated OpenAPI exception must remain valid in the managed contract."
  }

  assert {
    condition = (
      local.repository_standards_catalog["actions"] == local.repository_standards_documents["actions"] &&
      local.repository_standards_catalog["platform-workloads"] == local.repository_standards_documents["platform-workloads"] &&
      local.repository_standards_catalog["trip-side-kick"] == local.repository_standards_documents["trip-side-kick"]
    )
    error_message = "Representative aggregate catalog entries must exactly equal their per-repository contracts."
  }

  assert {
    condition = (
      local.repository_standards_catalog_variable.repository == "platform-devex" &&
      local.repository_standards_catalog_variable.name == "REPOSITORY_STANDARDS_CATALOG" &&
      contains(keys(local.repository_standards_workloads), "platform-devex") &&
      local.repository_standards_catalog["platform-devex"] == local.repository_standards_documents["platform-devex"]
    )
    error_message = "platform-devex must be an applicable catalog repository and the aggregate variable target."
  }

  assert {
    condition = (
      local.repository_standards_catalog_variable.value == jsonencode(local.repository_standards_catalog) &&
      local.repository_standards_catalog_base64_length <= local.repository_standards_catalog_max_base64_length &&
      local.repository_standards_catalog_max_bytes == 48000
    )
    error_message = "The deterministic aggregate catalog must remain below the conservative 48,000-byte GitHub variable bound."
  }

  assert {
    condition = alltrue(concat(
      [
        for name in ["status-pages", "41-bovet-street", "CoD4x_Server", "portal-bots"] :
        !contains(keys(local.repository_standards_variables), name)
      ],
      [
        for workload in local.all_workloads :
        !startswith(workload.name, "xi-") || !contains(keys(local.repository_standards_variables), workload.name)
      ]
    ))
    error_message = "Analysis exemptions and xi repositories must receive no repository standards variable."
  }
}
