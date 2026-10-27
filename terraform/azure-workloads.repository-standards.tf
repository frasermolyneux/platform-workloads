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
      length(keys(override)) == 1 &&
      length(setsubtract(keys(override), ["checkov"])) == 0 &&
      length(keys(override.checkov)) == 1 &&
      length(setsubtract(keys(override.checkov), ["exceptions"])) == 0 &&
      length(distinct([for exception in override.checkov.exceptions : exception.rule])) == length(override.checkov.exceptions) &&
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
        !can(regex("[\u0000-\u001F\u0085\u2028\u2029]", exception.reason))
      ]),
      false
    )
  }
  repository_standards_profiles = {
    for name, workload in local.repository_standards_workloads : name => (
      length(setintersection(
        workload.github.repository_analysis.profile.languages,
        ["terraform", "bicep"]
        )) > 0 ? local.repository_standards_profile_order : [
        "base",
      ]
    )
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
  repository_standards_documents = {
    for name in keys(local.repository_standards_workloads) : name => {
      version = "repository-standards-v1"
      managedFiles = {
        checkov = {
          version    = "checkov-v1"
          profiles   = local.repository_standards_profiles[name]
          exceptions = local.repository_standards_exceptions[name]
        }
      }
    }
  }
  repository_standards_documents_valid = {
    for name, document in local.repository_standards_documents : name => try(
      length(keys(document)) == 2 &&
      length(setsubtract(keys(document), ["version", "managedFiles"])) == 0 &&
      document.version == "repository-standards-v1" &&
      length(keys(document.managedFiles)) == 1 &&
      length(setsubtract(keys(document.managedFiles), ["checkov"])) == 0 &&
      length(keys(document.managedFiles.checkov)) == 3 &&
      length(setsubtract(keys(document.managedFiles.checkov), ["version", "profiles", "exceptions"])) == 0 &&
      document.managedFiles.checkov.version == "checkov-v1" &&
      jsonencode(document.managedFiles.checkov.profiles) == jsonencode(
        length(setintersection(
          local.repository_standards_workloads[name].github.repository_analysis.profile.languages,
          ["terraform", "bicep"]
          )) > 0 ? local.repository_standards_profile_order : [
          "base",
        ]
      ) &&
      alltrue([
        for profile in document.managedFiles.checkov.profiles :
        contains(local.repository_standards_profile_order, profile)
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
        !can(regex("[\u0000-\u001F\u0085\u2028\u2029]", exception.reason))
      ]),
      false
    )
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
    variables = local.repository_standards_variables
  }))

  lifecycle {
    precondition {
      condition = (
        length(setsubtract(keys(local.repository_standards_overrides), keys(local.repository_standards_workloads))) == 0 &&
        alltrue(values(local.repository_standards_overrides_valid)) &&
        alltrue(values(local.repository_standards_documents_valid)) &&
        jsonencode(sort(keys(local.repository_standards_variables))) == jsonencode(sort(keys(local.repository_standards_workloads))) &&
        alltrue([
          for name in keys(local.repository_standards_variables) :
          !startswith(name, "xi-") &&
          !can(local.repository_analysis_policies[name].profile.exemption)
        ])
      )
      error_message = "Repository standards require exact repository-standards-v1/checkov-v1 keys, deterministic supported profiles, bounded Checkov rule exceptions, and projection only to applicable non-xi analysis catalog rows."
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
