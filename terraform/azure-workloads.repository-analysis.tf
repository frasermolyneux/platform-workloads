locals {
  analysis_scoped_workloads = {
    for workload in local.all_workloads : workload.name => workload
    if !startswith(workload.name, "xi-")
  }
  repository_analysis_policies = {
    for name, workload in local.analysis_scoped_workloads : name => workload.github.repository_analysis
    if can(workload.github.repository_analysis)
  }
  analysis_languages = [
    "actions", "csharp", "cpp", "javascript", "typescript", "python", "php",
    "terraform", "bicep", "dockerfile", "ansible", "powershell", "shell"
  ]
  repository_analysis_valid = {
    for name, policy in local.repository_analysis_policies : name => try(
      length(setsubtract(keys(policy), ["profile", "sonar", "cadence"])) == 0 &&
      length(setsubtract(["profile", "sonar", "cadence"], keys(policy))) == 0 &&
      length(setsubtract(keys(policy.profile), ["version", "languages", "sonar", "exemption"])) == 0 &&
      policy.profile.version == "repository-analysis-v1" &&
      contains([true, false], policy.profile.sonar) &&
      length(distinct(policy.profile.languages)) == length(policy.profile.languages) &&
      alltrue([for language in policy.profile.languages : contains(local.analysis_languages, language)]) &&
      (can(policy.profile.exemption) ? (
        length(policy.profile.languages) == 0 && policy.profile.sonar == false &&
        policy.sonar == null && policy.cadence == null &&
        length(setsubtract(keys(policy.profile.exemption), ["kind", "reason", "reevaluate"])) == 0 &&
        contains(["documentation-only", "empty", "archived", "upstream-fork"], policy.profile.exemption.kind) &&
        alltrue([for value in [policy.profile.exemption.reason, policy.profile.exemption.reevaluate] :
        length(trimspace(value)) > 0 && length(value) <= 600])
        ) : (
        length(policy.profile.languages) > 0 &&
        length(setsubtract(keys(policy.cadence), [
          "dailyFreshness", "fullRescanMaximumHours", "defaultBranchCancellation", "dispatch"
        ])) == 0 &&
        length(setsubtract(keys(policy.cadence.dispatch), [
          "expectedRevision", "force", "defaultBranchOnly"
        ])) == 0 &&
        policy.cadence.dailyFreshness == true && policy.cadence.fullRescanMaximumHours == 168 &&
        policy.cadence.defaultBranchCancellation == false &&
        policy.cadence.dispatch.expectedRevision == true && policy.cadence.dispatch.force == true &&
        policy.cadence.dispatch.defaultBranchOnly == true &&
        (policy.profile.sonar ? (
          local.analysis_scoped_workloads[name].github.visibility == "public" &&
          length(setsubtract(keys(policy.sonar), ["recipe", "build"])) == 0 &&
          length(keys(policy.sonar.recipe)) == 5 &&
          length(setsubtract(keys(policy.sonar.recipe), [
            "version", "driver", "projectKey", "sourceDirectory", "coverage"
          ])) == 0 &&
          policy.sonar.recipe.version == 1 &&
          policy.sonar.recipe.projectKey == "frasermolyneux_${name}" &&
          can(regex("^(\\.|[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*)$", policy.sonar.recipe.sourceDirectory)) &&
          !contains(split("/", policy.sonar.recipe.sourceDirectory), "..") &&
          contains(["cobertura", "not-applicable"], policy.sonar.recipe.coverage) &&
          (policy.sonar.recipe.driver == "dotnet" ? (
            contains(policy.profile.languages, "csharp") &&
            length(keys(policy.sonar.build)) == 6 &&
            length(setsubtract(keys(policy.sonar.build), [
              "kind", "sdk", "globalJson", "solution", "skipFormat", "tests"
            ])) == 0 &&
            contains(["dotnet", "netfx"], policy.sonar.build.kind) &&
            can(regex("^(\\.|[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*)$", policy.sonar.build.solution)) &&
            !contains(split("/", policy.sonar.build.solution), "..") &&
            length(policy.sonar.build.sdk) > 0 && length(policy.sonar.build.sdk) <= 4 &&
            alltrue([for sdk in policy.sonar.build.sdk : can(regex("^[0-9]+\\.[0-9]+\\.(x|[0-9]+|[1-9]xx)$", sdk))]) &&
            (policy.sonar.build.globalJson == null ? true : (
              can(regex("^[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*$", policy.sonar.build.globalJson)) &&
              !contains(split("/", policy.sonar.build.globalJson), "..") &&
              basename(policy.sonar.build.globalJson) == "global.json"
            )) &&
            contains([true, false], policy.sonar.build.tests) &&
            contains([true, false], policy.sonar.build.skipFormat) &&
            (policy.sonar.recipe.coverage == "cobertura") == policy.sonar.build.tests &&
            (policy.sonar.build.kind != "netfx" || (!policy.sonar.build.tests && policy.sonar.build.skipFormat))
            ) : (policy.sonar.recipe.driver == "cpp" ? (
              contains(policy.profile.languages, "cpp") && policy.sonar.build.kind == "cmake" &&
              length(keys(policy.sonar.build)) == 4 &&
              length(setsubtract(keys(policy.sonar.build), ["kind", "configureArgs", "buildArgs", "testArgs"])) == 0 &&
              policy.sonar.recipe.coverage == "not-applicable" &&
              length(policy.sonar.build.configureArgs) > 0 && length(policy.sonar.build.configureArgs) <= 32 &&
              contains(policy.sonar.build.configureArgs, "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON") &&
              alltrue([for arg in policy.sonar.build.configureArgs : contains([
                "-DCMAKE_BUILD_TYPE=Release", "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON",
              "-DPORTAL_COD4X_BUILD_PLUGIN_BINARY=OFF"], arg)]) &&
              jsonencode(policy.sonar.build.buildArgs) == jsonencode(["--config", "Release"]) &&
              jsonencode(policy.sonar.build.testArgs) == jsonencode(["--output-on-failure", "--build-config", "Release"])
              ) : (
              policy.sonar.recipe.driver == "cli" && policy.sonar.build.kind == "script" &&
              length(keys(policy.sonar.build)) == 3 &&
              length(setsubtract(keys(policy.sonar.build), ["kind", "nodeVersion", "npmInstall"])) == 0 &&
              length(setintersection(policy.profile.languages, ["javascript", "typescript", "python", "php"])) > 0 &&
              policy.sonar.recipe.coverage == "not-applicable" &&
              contains(["20.x", "22"], policy.sonar.build.nodeVersion) &&
              contains([true, false], policy.sonar.build.npmInstall)
          )))
        ) : policy.sonar == null)
      )),
    false)
  }
  repository_analysis_variables = flatten([
    for name, policy in local.repository_analysis_policies : concat([
      { repository = name, name = "REPOSITORY_ANALYSIS_PROFILE", value = jsonencode(policy.profile) },
      { repository = name, name = "REPOSITORY_ANALYSIS_CADENCE", value = jsonencode(policy.cadence) }
      ], policy.sonar == null ? [] : [
      { repository = name, name = "REPOSITORY_ANALYSIS_SONAR_RECIPE", value = jsonencode(policy.sonar.recipe) },
      { repository = name, name = "REPOSITORY_ANALYSIS_BUILD", value = jsonencode(policy.sonar.build) }
    ]) if !can(policy.profile.exemption)
  ])
}

resource "terraform_data" "repository_analysis_contract" {
  input = sha256(jsonencode({
    policies  = local.repository_analysis_policies
    variables = local.repository_analysis_variables
  }))

  lifecycle {
    precondition {
      condition = (
        length(setsubtract(keys(local.analysis_scoped_workloads), keys(local.repository_analysis_policies))) == 0 &&
        alltrue(values(local.repository_analysis_valid))
      )
      error_message = "Every non-xi catalog row requires a valid source analysis policy or explicit applicability exemption; recipes, visibility and weekly freshness must match the supported contract."
    }
  }
}

resource "github_actions_variable" "repository_analysis" {
  for_each = {
    for variable in local.repository_analysis_variables :
    "${variable.repository}:${variable.name}" => variable
  }

  repository = try(local.analysis_scoped_workloads[each.value.repository].github.manage_repository, true) ? (
    github_repository.workload[each.value.repository].name
  ) : each.value.repository
  variable_name = each.value.name
  value         = each.value.value
  depends_on    = [terraform_data.repository_analysis_contract]
}
