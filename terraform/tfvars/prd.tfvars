environment = "prd"
location    = "uksouth"
instance    = "01"

subscription_id = "7760848c-794d-4a19-8cb2-52f71a21ac2b"

platform_workloads_backend_resource_group_name  = "rg-tf-platform-workloads-prd-uksouth-01"
platform_workloads_backend_storage_account_name = "sadz9ita659lj9xb3"

tags = {
  Environment = "prd",
  Workload    = "platform",
  DeployedBy  = "GitHub-Terraform",
  Git         = "https://github.com/frasermolyneux/platform-workloads"
}

subscriptions = {
  sub-enterprise-devtest-legacy = {
    name            = "sub-enterprise-devtest-legacy"
    subscription_id = "1b5b28ed-1365-4a48-b285-80f80a6aaa1b"
    environment     = "dev"
  },
  sub-fm-geolocation-prd = {
    name            = "sub-fm-geolocation-prd"
    subscription_id = "d3b204ab-7c2b-47f7-8d5a-de19e85591e7"
    environment     = "prd"
  },
  sub-mx-consulting-prd = {
    name            = "sub-mx-consulting-prd"
    subscription_id = "655da25d-da46-40c0-8e81-5debe2dcd024"
    environment     = "prd"
  },
  sub-platform-connectivity = {
    name            = "sub-platform-connectivity"
    subscription_id = "db34f572-8b71-40d6-8f99-f29a27612144"
    environment     = "prd"
  },
  sub-platform-identity = {
    name            = "sub-platform-identity"
    subscription_id = "c391a150-f992-41a6-bc81-ebc22bc64376"
    environment     = "prd"
  },
  sub-platform-management = {
    name            = "sub-platform-management"
    subscription_id = "7760848c-794d-4a19-8cb2-52f71a21ac2b"
    environment     = "prd"
  },
  sub-platform-shared = {
    name            = "sub-platform-shared"
    subscription_id = "903b6685-c12a-4703-ac54-7ec1ff15ca43"
    environment     = "prd"
  },
  sub-talkwithtiles-prd = {
    name            = "sub-talkwithtiles-prd"
    subscription_id = "e1e5de62-3573-4b44-a52b-0f1431675929"
    environment     = "prd"
  },
  sub-visualstudio-enterprise = {
    name            = "sub-visualstudio-enterprise"
    subscription_id = "6cad03c1-9e98-4160-8ebe-64dd30f1bbc7"
    environment     = "dev"
  },
  sub-visualstudio-enterprise-legacy = {
    name            = "sub-visualstudio-enterprise-legacy"
    subscription_id = "d68448b0-9947-46d7-8771-baa331a3063a"
    environment     = "dev"
  },
  sub-xi-demomanager-prd = {
    name            = "sub-xi-demomanager-prd"
    subscription_id = "845766d6-b73f-49aa-a9f6-eaf27e20b7a8"
    environment     = "prd"
  },
  sub-xi-portal-prd = {
    name            = "sub-xi-portal-prd"
    subscription_id = "32444f38-32f4-409f-889c-8e8aa2b5b4d1"
    environment     = "prd"
  },
  sub-finances-prd = {
    name            = "sub-finances-prd"
    subscription_id = "957a7d34-8562-4098-bb4c-072e08386d07"
    environment     = "prd"
  },
  sub-molyneux-me-dev = {
    name            = "sub-molyneux-me-dev"
    subscription_id = "ef3cc6c2-159e-4890-9193-13673dded835"
    environment     = "dev"
  },
  sub-molyneux-me-prd = {
    name            = "sub-molyneux-me-prd"
    subscription_id = "3cc59319-eb1e-4b52-b19e-09a49f9db2e7"
    environment     = "prd"
  }
}

azuredevops_projects = [
  {
    name        = "Molyneux.IO"
    description = "Personal projects generally deployed to the Molyneux.IO platform."

    visibility = "private"

    version_control    = "Git"
    work_item_template = "Agile"

    add_nuget_variable_group      = true
    add_sonarcloud_variable_group = true

    features = {
      "boards"       = "disabled"
      "repositories" = "disabled"
      "pipelines"    = "enabled"
      "testplans"    = "disabled"
      "artifacts"    = "disabled"
    }
  },
  {
    name        = "XtremeIdiots"
    description = "XtremeIdiots projects generally deployed to the Molyneux.IO platform or XtremeIdiots hosted."

    visibility = "private"

    version_control    = "Git"
    work_item_template = "Agile"

    add_nuget_variable_group      = true
    add_sonarcloud_variable_group = true

    features = {
      "boards"       = "disabled"
      "repositories" = "disabled"
      "pipelines"    = "enabled"
      "testplans"    = "disabled"
      "artifacts"    = "disabled"
    }
  }
]
