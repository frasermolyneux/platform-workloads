locals {
  repository_standards_profile_order = [
    "base",
    "cost-optimised",
    "public-endpoints",
    "app-service-standard",
    "central-observability",
  ]
  repository_standards_checkov_exception_allowlist = [
    "CKV_OPENAPI_21",
    "CKV_SECRET_6",
  ]
  repository_standards_editorconfig_profiles = [
    "curated-low-noise",
    "actionable-only",
  ]
  repository_standards_sonar_profiles = [
    "actionable-only",
    "common-vendor-assets",
  ]
  repository_standards_eslint_profiles = [
    "common-vendor-assets",
  ]
  repository_standards_resource_scoped_profiles = {
    cost-optimised = {
      rule    = "CKV_AZURE_225"
      profile = "cost-optimised-resource-scoped"
    }
    public-endpoints = {
      rule    = "CKV_AZURE_109"
      profile = "public-endpoints-resource-scoped"
    }
  }
  repository_standards_workloads = {
    for name, policy in local.repository_analysis_policies : name => local.analysis_scoped_workloads[name]
    if !can(policy.profile.exemption)
  }
  repository_standards_overrides = {
    for name, workload in local.analysis_scoped_workloads : name => workload.github.repository_standards
    if can(workload.github.repository_standards)
  }
  repository_standards_overrides_valid = {
    for name, override in local.repository_standards_overrides : name => try(
      contains([1, 2], length(keys(override))) &&
      length(setsubtract(keys(override), ["checkov", "sonar"])) == 0 &&
      (!can(override.checkov) || (
        contains([1, 2], length(keys(override.checkov))) &&
        length(setsubtract(keys(override.checkov), ["exceptions", "resource_scoped_checks"])) == 0 &&
        can(override.checkov.exceptions) &&
        length(distinct([for exception in override.checkov.exceptions : exception.rule])) == length(override.checkov.exceptions) &&
        length(distinct(try(override.checkov.resource_scoped_checks, []))) == length(try(override.checkov.resource_scoped_checks, [])) &&
        alltrue([
          for rule in try(override.checkov.resource_scoped_checks, []) :
          contains([for variant in values(local.repository_standards_resource_scoped_profiles) : variant.rule], rule)
        ]) &&
        (length(try(override.checkov.resource_scoped_checks, [])) == 0 || length(setintersection(
          local.repository_standards_workloads[name].github.repository_analysis.profile.languages,
          ["terraform", "bicep"]
        )) > 0) &&
        alltrue([
          for exception in override.checkov.exceptions :
          length(keys(exception)) == 2 &&
          length(setsubtract(keys(exception), ["rule", "reason"])) == 0 &&
          length(setsubtract(["rule", "reason"], keys(exception))) == 0 &&
          can(regex("^CKV2?_[A-Z0-9]+(_[A-Z0-9]+)*_[0-9]+$", exception.rule)) &&
          contains(local.repository_standards_checkov_exception_allowlist, exception.rule) &&
          exception.reason == trimspace(exception.reason) &&
          length(exception.reason) >= 10 &&
          length(exception.reason) <= 600 &&
          !can(regex("[\u0000-\u001F\u007F-\u009F\u2028\u2029\uFFFE\uFFFF]", exception.reason))
        ])
      )) &&
      (!can(override.sonar) || (
        local.repository_standards_workloads[name].github.repository_analysis.profile.sonar &&
        length(keys(override.sonar)) == 1 &&
        length(setsubtract(keys(override.sonar), ["exclusions"])) == 0 &&
        can(override.sonar.exclusions) &&
        length(override.sonar.exclusions) <= 59 &&
        length(distinct([for exclusion in override.sonar.exclusions : exclusion.pattern])) == length(override.sonar.exclusions) &&
        alltrue([
          for exclusion in override.sonar.exclusions :
          length(keys(exclusion)) == 2 &&
          length(setsubtract(keys(exclusion), ["pattern", "reason"])) == 0 &&
          can(regex("^[A-Za-z0-9._*?/-]+$", exclusion.pattern)) &&
          length(exclusion.pattern) <= 240 &&
          !startswith(exclusion.pattern, "/") &&
          !startswith(exclusion.pattern, "**/") &&
          !strcontains(exclusion.pattern, "\\") &&
          !strcontains(exclusion.pattern, ",") &&
          !contains(split("/", exclusion.pattern), ".") &&
          !contains(split("/", exclusion.pattern), "..") &&
          length(split("/", exclusion.pattern)) >= 3 &&
          (
            element(reverse(split("/", exclusion.pattern)), 0) != "**" ||
            contains(
              ["less", "scss", "vendor", "lib"],
              element(reverse(split("/", exclusion.pattern)), 1)
            )
          ) &&
          exclusion.reason == trimspace(exclusion.reason) &&
          length(exclusion.reason) >= 10 &&
          length(exclusion.reason) <= 240 &&
          !can(regex("[\u0000-\u001F\u007F-\u009F\u2028\u2029\uFFFE\uFFFF]", exclusion.reason))
        ])
      )),
      false
    )
  }
  repository_standards_default_profiles = {
    for name, workload in local.repository_standards_workloads : name => (
      length(setintersection(
        workload.github.repository_analysis.profile.languages,
        ["terraform", "bicep"]
        )) > 0 ? local.repository_standards_profile_order : [
        "base",
      ]
    )
  }
  repository_standards_profiles = {
    for name, profiles in local.repository_standards_default_profiles : name => [
      for profile in profiles :
      contains(
        try(local.repository_standards_overrides[name].checkov.resource_scoped_checks, []),
        try(local.repository_standards_resource_scoped_profiles[profile].rule, "")
      ) ? local.repository_standards_resource_scoped_profiles[profile].profile : profile
    ]
  }
  repository_standards_exceptions = {
    for name in keys(local.repository_standards_workloads) : name => try([
      for encoded in sort([
        for exception in local.repository_standards_overrides[name].checkov.exceptions :
        jsonencode({
          rule   = exception.rule
          reason = exception.reason
        })
      ]) : jsondecode(encoded)
    ], [])
  }
  repository_standards_sonar_exclusions = {
    for name in keys(local.repository_standards_workloads) : name => try([
      for encoded in sort([
        for exclusion in local.repository_standards_overrides[name].sonar.exclusions :
        jsonencode({
          pattern = exclusion.pattern
          reason  = exclusion.reason
        })
      ]) : jsondecode(encoded)
    ], [])
  }
  repository_standards_documents = {
    for name in keys(local.repository_standards_workloads) : name => {
      version = "repository-standards-v1"
      managedFiles = merge(
        {
          checkov = {
            version    = "checkov-v1"
            profiles   = local.repository_standards_profiles[name]
            exceptions = local.repository_standards_exceptions[name]
          }
        },
        contains(
          local.repository_standards_workloads[name].github.repository_analysis.profile.languages,
          "csharp"
          ) ? {
          editorconfig = {
            version  = "dotnet-editorconfig-v1"
            profiles = local.repository_standards_editorconfig_profiles
          }
        } : {},
        local.repository_standards_workloads[name].github.repository_analysis.profile.sonar ? {
          sonar = {
            version    = "sonar-policy-v1"
            profiles   = local.repository_standards_sonar_profiles
            exclusions = local.repository_standards_sonar_exclusions[name]
          }
        } : {},
        length(setintersection(
          local.repository_standards_workloads[name].github.repository_analysis.profile.languages,
          ["javascript", "typescript"]
          )) > 0 ? {
          eslint = {
            version  = "eslint-ignore-v1"
            profiles = local.repository_standards_eslint_profiles
          }
        } : {}
      )
    }
  }
  repository_standards_documents_valid = {
    for name, document in local.repository_standards_documents : name => try(
      length(keys(document)) == 2 &&
      length(setsubtract(keys(document), ["version", "managedFiles"])) == 0 &&
      document.version == "repository-standards-v1" &&
      length(keys(document.managedFiles)) == 1 +
      (contains(local.repository_standards_workloads[name].github.repository_analysis.profile.languages, "csharp") ? 1 : 0) +
      (local.repository_standards_workloads[name].github.repository_analysis.profile.sonar ? 1 : 0) +
      (length(setintersection(local.repository_standards_workloads[name].github.repository_analysis.profile.languages, ["javascript", "typescript"])) > 0 ? 1 : 0) &&
      length(setsubtract(keys(document.managedFiles), ["checkov", "editorconfig", "sonar", "eslint"])) == 0 &&
      length(keys(document.managedFiles.checkov)) == 3 &&
      length(setsubtract(keys(document.managedFiles.checkov), ["version", "profiles", "exceptions"])) == 0 &&
      document.managedFiles.checkov.version == "checkov-v1" &&
      jsonencode([
        for profile in document.managedFiles.checkov.profiles : trimsuffix(profile, "-resource-scoped")
      ]) == jsonencode(local.repository_standards_default_profiles[name]) &&
      alltrue([
        for profile in document.managedFiles.checkov.profiles :
        contains(local.repository_standards_profile_order, profile) || anytrue([
          for variant in values(local.repository_standards_resource_scoped_profiles) :
          profile == variant.profile &&
          contains(try(local.repository_standards_overrides[name].checkov.resource_scoped_checks, []), variant.rule)
        ])
      ]) &&
      alltrue([
        for original, variant in local.repository_standards_resource_scoped_profiles :
        !contains(try(local.repository_standards_overrides[name].checkov.resource_scoped_checks, []), variant.rule) ||
        (contains(document.managedFiles.checkov.profiles, variant.profile) && !contains(document.managedFiles.checkov.profiles, original))
      ]) &&
      alltrue([
        for exception in document.managedFiles.checkov.exceptions :
        length(keys(exception)) == 2 &&
        length(setsubtract(keys(exception), ["rule", "reason"])) == 0 &&
        can(regex("^CKV2?_[A-Z0-9]+(_[A-Z0-9]+)*_[0-9]+$", exception.rule)) &&
        contains(local.repository_standards_checkov_exception_allowlist, exception.rule) &&
        exception.reason == trimspace(exception.reason) &&
        length(exception.reason) >= 10 &&
        length(exception.reason) <= 600 &&
        !can(regex("[\u0000-\u001F\u007F-\u009F\u2028\u2029\uFFFE\uFFFF]", exception.reason))
      ]) &&
      (
        contains(
          local.repository_standards_workloads[name].github.repository_analysis.profile.languages,
          "csharp"
        ) == can(document.managedFiles.editorconfig)
      ) &&
      (
        !can(document.managedFiles.editorconfig) || (
          length(keys(document.managedFiles.editorconfig)) == 2 &&
          length(setsubtract(keys(document.managedFiles.editorconfig), ["version", "profiles"])) == 0 &&
          document.managedFiles.editorconfig.version == "dotnet-editorconfig-v1" &&
          jsonencode(document.managedFiles.editorconfig.profiles) == jsonencode(local.repository_standards_editorconfig_profiles)
        )
      ) &&
      (
        local.repository_standards_workloads[name].github.repository_analysis.profile.sonar ==
        can(document.managedFiles.sonar)
      ) &&
      (
        !can(document.managedFiles.sonar) || (
          length(keys(document.managedFiles.sonar)) == 3 &&
          length(setsubtract(keys(document.managedFiles.sonar), ["version", "profiles", "exclusions"])) == 0 &&
          document.managedFiles.sonar.version == "sonar-policy-v1" &&
          jsonencode(document.managedFiles.sonar.profiles) == jsonencode(local.repository_standards_sonar_profiles) &&
          jsonencode(document.managedFiles.sonar.exclusions) == jsonencode(local.repository_standards_sonar_exclusions[name])
        )
      ) &&
      (
        (length(setintersection(
          local.repository_standards_workloads[name].github.repository_analysis.profile.languages,
          ["javascript", "typescript"]
        )) > 0) == can(document.managedFiles.eslint)
      ) &&
      (
        !can(document.managedFiles.eslint) || (
          length(keys(document.managedFiles.eslint)) == 2 &&
          length(setsubtract(keys(document.managedFiles.eslint), ["version", "profiles"])) == 0 &&
          document.managedFiles.eslint.version == "eslint-ignore-v1" &&
          jsonencode(document.managedFiles.eslint.profiles) == jsonencode(local.repository_standards_eslint_profiles)
        )
      ),
      false
    )
  }
  repository_standards_catalog = {
    for name in sort(keys(local.repository_standards_documents)) :
    name => local.repository_standards_documents[name]
  }
  repository_standards_catalog_json              = jsonencode(local.repository_standards_catalog)
  repository_standards_catalog_max_bytes         = 48000
  repository_standards_catalog_base64_length     = length(base64encode(local.repository_standards_catalog_json))
  repository_standards_catalog_max_base64_length = 4 * ceil(local.repository_standards_catalog_max_bytes / 3)
  repository_standards_catalog_variable = {
    repository = "platform-devex"
    name       = "REPOSITORY_STANDARDS_CATALOG"
    value      = local.repository_standards_catalog_json
  }
  repository_standards_variables = {
    for name, document in local.repository_standards_documents : name => {
      repository = name
      name       = "REPOSITORY_STANDARDS"
      value      = jsonencode(document)
    }
  }
}

resource "terraform_data" "repository_standards_contract" {
  input = sha256(jsonencode({
    overrides = local.repository_standards_overrides
    documents = local.repository_standards_documents
    catalog   = local.repository_standards_catalog
    variables = local.repository_standards_variables
  }))

  lifecycle {
    precondition {
      condition = (
        length(setsubtract(keys(local.repository_standards_overrides), keys(local.repository_standards_workloads))) == 0 &&
        alltrue(values(local.repository_standards_overrides_valid)) &&
        alltrue(values(local.repository_standards_documents_valid)) &&
        jsonencode(sort(keys(local.repository_standards_catalog))) == jsonencode(sort(keys(local.repository_standards_workloads))) &&
        alltrue([
          for name in keys(local.repository_standards_catalog) :
          local.repository_standards_catalog[name] == local.repository_standards_documents[name]
        ]) &&
        contains(keys(local.repository_standards_workloads), local.repository_standards_catalog_variable.repository) &&
        local.repository_standards_catalog_base64_length <= local.repository_standards_catalog_max_base64_length &&
        jsonencode(sort(keys(local.repository_standards_variables))) == jsonencode(sort(keys(local.repository_standards_workloads))) &&
        alltrue([
          for name in keys(local.repository_standards_variables) :
          !startswith(name, "xi-") &&
          !can(local.repository_analysis_policies[name].profile.exemption)
        ])
      )
      error_message = "Repository standards require exact repository-standards-v1 managed-file keys, deterministic Checkov, .NET, Sonar and ESLint profiles, bounded reviewed exceptions, an applicable platform-devex aggregate catalog below 48 KB, and projection only to applicable non-xi analysis catalog rows."
    }
  }
}

resource "github_actions_variable" "repository_standards" {
  for_each = local.repository_standards_variables

  repository = try(local.repository_standards_workloads[each.key].github.manage_repository, true) ? (
    github_repository.workload[each.key].name
  ) : each.key
  variable_name = each.value.name
  value         = each.value.value
  depends_on    = [terraform_data.repository_standards_contract]
}

resource "github_actions_variable" "repository_standards_catalog" {
  repository = try(local.repository_standards_workloads[local.repository_standards_catalog_variable.repository].github.manage_repository, true) ? (
    github_repository.workload[local.repository_standards_catalog_variable.repository].name
  ) : local.repository_standards_catalog_variable.repository
  variable_name = local.repository_standards_catalog_variable.name
  value         = local.repository_standards_catalog_variable.value
  depends_on    = [terraform_data.repository_standards_contract]
}
