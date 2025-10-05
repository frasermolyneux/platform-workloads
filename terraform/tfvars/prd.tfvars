environment = "prd"
location    = "uksouth"
instance    = "01"

subscription_id = "7760848c-794d-4a19-8cb2-52f71a21ac2b"

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
  },
  sub-fm-geolocation-prd = {
    name            = "sub-fm-geolocation-prd"
    subscription_id = "d3b204ab-7c2b-47f7-8d5a-de19e85591e7"
  },
  sub-mx-consulting-prd = {
    name            = "sub-mx-consulting-prd"
    subscription_id = "655da25d-da46-40c0-8e81-5debe2dcd024"
  },
  sub-platform-connectivity = {
    name            = "sub-platform-connectivity"
    subscription_id = "db34f572-8b71-40d6-8f99-f29a27612144"
  },
  sub-platform-identity = {
    name            = "sub-platform-identity"
    subscription_id = "c391a150-f992-41a6-bc81-ebc22bc64376"
  },
  sub-platform-management = {
    name            = "sub-platform-management"
    subscription_id = "7760848c-794d-4a19-8cb2-52f71a21ac2b"
  },
  sub-platform-strategic = {
    name            = "sub-platform-strategic"
    subscription_id = "903b6685-c12a-4703-ac54-7ec1ff15ca43"
  },
  sub-talkwithtiles-prd = {
    name            = "sub-talkwithtiles-prd"
    subscription_id = "e1e5de62-3573-4b44-a52b-0f1431675929"
  },
  sub-visualstudio-enterprise = {
    name            = "sub-visualstudio-enterprise"
    subscription_id = "d68448b0-9947-46d7-8771-baa331a3063a"
  },
  sub-xi-demomanager-prd = {
    name            = "sub-xi-demomanager-prd"
    subscription_id = "845766d6-b73f-49aa-a9f6-eaf27e20b7a8"
  },
  sub-xi-portal-prd = {
    name            = "sub-xi-portal-prd"
    subscription_id = "32444f38-32f4-409f-889c-8e8aa2b5b4d1"
  },
  sub-finances-prd = {
    name            = "sub-finances-prd"
    subscription_id = "957a7d34-8562-4098-bb4c-072e08386d07"
  },
  sub-molyneux-me-dev = {
    name            = "sub-molyneux-me-dev"
    subscription_id = "ef3cc6c2-159e-4890-9193-13673dded835"
  },
  sub-molyneux-me-prd = {
    name            = "sub-molyneux-me-prd"
    subscription_id = "3cc59319-eb1e-4b52-b19e-09a49f9db2e7"
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

workloads = [
  // Bicep Modules Workload
  {
    name = "bicep-modules"
    github = {
      description = "Bicep module repository; this contains Bicep modules that are published to an ACR for use in many projects. Bicep modules are pushed to ACR with an Azure DevOps pipeline."
      topics      = ["azure", "bicep", "azure-devops-pipelines"]
      visibility  = "public"
    }
    environments = [
      {
        name           = "Production"
        subscription   = "sub-platform-strategic"
        devops_project = "Molyneux.IO"
        role_assignments = [
          {
            role_definitions = ["Reader"] // Reader on the subscription only to allow Azure Login; no other permissions required on a subscription level
            scope            = "sub-platform-strategic"
          }
        ]
      }
    ]
  },

  // XtremeIdiots Portal Workloads
  {
    name = "portal-environments"
    github = {
      description = "Part of XtremeIdiots Portal solution; environment configuration and management. Deployed using Terraform and GitHub Actions."
      topics      = ["azure", "terraform", "github-actions"]

      add_sonarcloud_secrets = true
      add_nuget_environment  = true

      visibility = "public"
    }
    environments = [
      {
        name                    = "Development"
        subscription            = "sub-visualstudio-enterprise"
        connect_to_github       = true
        configure_for_terraform = true
        role_assignments = [
          {
            role_definitions = ["Owner", "Key Vault Secrets Officer", "App Configuration Data Owner"] // Owner is required to be able to set RBAC role assignments
            scope            = "sub-visualstudio-enterprise"
          }
        ]
        directory_roles = [
          "Cloud application administrator",
          "Directory Writers" // Required to be able to create SQL AAD Admin Groups
        ]
      },
      {
        name                    = "Production"
        subscription            = "sub-xi-portal-prd"
        connect_to_github       = true
        configure_for_terraform = true
        role_assignments = [
          {
            role_definitions = ["Owner", "Key Vault Secrets Officer", "App Configuration Data Owner"] // Owner is required to be able to set RBAC role assignments
            scope            = "sub-xi-portal-prd"
          }
        ]
        directory_roles = [
          "Cloud application administrator",
          "Directory Writers" // Required to be able to create SQL AAD Admin Groups
        ]
      }
    ]
  },
  {
    name = "portal-core"
    github = {
      description = "Part of XtremeIdiots Portal solution; creates the application platform. Deployed using Terraform and GitHub Actions."
      topics      = ["azure", "terraform", "github-actions", "api-management", "app-insights", "service-bus", "app-service-plan"]

      add_sonarcloud_secrets = true
      add_nuget_environment  = false

      visibility = "public"
    }
    environments = [
      {
        name                            = "Development"
        subscription                    = "sub-visualstudio-enterprise"
        connect_to_github               = true
        configure_for_terraform         = true
        requires_terraform_state_access = ["portal-environments"]
        role_assignments = [
          {
            role_definitions = ["Owner", "Key Vault Secrets Officer", "Storage Blob Data Contributor"] // Owner is required to be able to set RBAC role assignments
            scope            = "sub-visualstudio-enterprise"
          }
        ]
        directory_roles = [
          "Cloud application administrator"
        ]
      },
      {
        name                            = "Production"
        subscription                    = "sub-xi-portal-prd"
        connect_to_github               = true
        configure_for_terraform         = true
        requires_terraform_state_access = ["portal-environments"]
        role_assignments = [
          {
            role_definitions = ["Owner", "Key Vault Secrets Officer", "Storage Blob Data Contributor"] // Owner is required to be able to set RBAC role assignments
            scope            = "sub-xi-portal-prd"
          }
        ]
        directory_roles = [
          "Cloud application administrator"
        ]
      }
    ]
  },
  {
    name = "portal-common-messaging"
    github = {
      description = "Part of XtremeIdiots Portal solution; common messaging abstractions via service bus. Deployed using Terraform and GitHub Actions."
      topics      = ["azure", "terraform", "github-actions"]

      add_sonarcloud_secrets = true
      add_nuget_environment  = true

      visibility = "public"
    }
    environments = [
      {
        name                            = "Development"
        subscription                    = "sub-visualstudio-enterprise"
        connect_to_github               = true
        configure_for_terraform         = true
        requires_terraform_state_access = ["portal-core", "portal-environments"]
        role_assignments = [
          {
            role_definitions = ["Owner", "Key Vault Secrets Officer", "Storage Blob Data Contributor"] // Owner is required to be able to set RBAC role assignments
            scope            = "sub-visualstudio-enterprise"
          }
        ]
        directory_roles = [
          "Cloud application administrator"
        ]
      },
      {
        name                            = "Production"
        subscription                    = "sub-xi-portal-prd"
        connect_to_github               = true
        configure_for_terraform         = true
        requires_terraform_state_access = ["portal-core", "portal-environments"]
        role_assignments = [
          {
            role_definitions = ["Owner", "Key Vault Secrets Officer", "Storage Blob Data Contributor"] // Owner is required to be able to set RBAC role assignments
            scope            = "sub-xi-portal-prd"
          }
        ]
        directory_roles = [
          "Cloud application administrator"
        ]
      }
    ]
  },
  {
    name = "portal-event-abstractions"
    github = {
      description = "Part of XtremeIdiots Portal solution; event abstractions for the service. Deployed using Terraform and GitHub Actions."
      topics      = ["azure", "terraform", "github-actions"]

      add_sonarcloud_secrets = true
      add_nuget_environment  = true

      visibility = "public"
    }
  },
  {
    name = "portal-event-ingest"
    github = {
      description = "Part of XtremeIdiots Portal solution; event ingest into the service. Deployed using Terraform and GitHub Actions."
      topics      = ["azure", "terraform", "github-actions", "api-management-api", "app-insights", "service-bus", "function-app", "key-vault", "app-registration"]

      add_sonarcloud_secrets = true
      add_nuget_environment  = true

      visibility = "public"
    }
    environments = [
      {
        name                            = "Development"
        subscription                    = "sub-visualstudio-enterprise"
        connect_to_github               = true
        configure_for_terraform         = true
        requires_terraform_state_access = ["portal-core", "portal-environments"]
        role_assignments = [
          {
            role_definitions = ["Owner", "Key Vault Secrets Officer", "Storage Blob Data Contributor"] // Owner is required to be able to set RBAC role assignments
            scope            = "sub-visualstudio-enterprise"
          }
        ]
        directory_roles = [
          "Cloud application administrator"
        ]
      },
      {
        name                            = "Production"
        subscription                    = "sub-xi-portal-prd"
        connect_to_github               = true
        configure_for_terraform         = true
        requires_terraform_state_access = ["portal-core", "portal-environments"]
        role_assignments = [
          {
            role_definitions = ["Owner", "Key Vault Secrets Officer", "Storage Blob Data Contributor"] // Owner is required to be able to set RBAC role assignments
            scope            = "sub-xi-portal-prd"
          }
        ]
        directory_roles = [
          "Cloud application administrator"
        ]
      }
    ]
  },
  {
    name = "portal-event-processor"
    github = {
      description = "Part of XtremeIdiots Portal solution; event processing into the service. Deployed using Terraform and GitHub Actions."
      topics      = ["azure", "terraform", "github-actions"]

      add_sonarcloud_secrets = true
      add_nuget_environment  = true

      visibility = "public"
    }
    environments = [
      {
        name                            = "Development"
        subscription                    = "sub-visualstudio-enterprise"
        connect_to_github               = true
        configure_for_terraform         = true
        requires_terraform_state_access = ["portal-core", "portal-environments"]
        role_assignments = [
          {
            role_definitions = ["Owner", "Key Vault Secrets Officer", "Storage Blob Data Contributor"] // Owner is required to be able to set RBAC role assignments
            scope            = "sub-visualstudio-enterprise"
          }
        ]
        directory_roles = [
          "Cloud application administrator"
        ]
      },
      {
        name                            = "Production"
        subscription                    = "sub-xi-portal-prd"
        connect_to_github               = true
        configure_for_terraform         = true
        requires_terraform_state_access = ["portal-core", "portal-environments"]
        role_assignments = [
          {
            role_definitions = ["Owner", "Key Vault Secrets Officer", "Storage Blob Data Contributor"] // Owner is required to be able to set RBAC role assignments
            scope            = "sub-xi-portal-prd"
          }
        ]
        directory_roles = [
          "Cloud application administrator"
        ]
      }
    ]
  },
  {
    name = "portal-repository"
    github = {
      description = "Part of XtremeIdiots Portal solution; player and server data storage. Deployed using Terraform and GitHub Actions."
      topics      = ["azure", "terraform", "github-actions", "sql-database", "key-vault", "app-registration", "app-insights", "app-service", "aad-groups"]

      add_sonarcloud_secrets = true
      add_nuget_environment  = true

      visibility = "public"
    }
    environments = [
      {
        name                            = "Development"
        subscription                    = "sub-visualstudio-enterprise"
        connect_to_github               = true
        configure_for_terraform         = true
        requires_terraform_state_access = ["portal-core", "portal-environments"]
        role_assignments = [
          {
            role_definitions = ["Owner", "Key Vault Secrets Officer", "Storage Blob Data Contributor"] // Owner is required to be able to set RBAC role assignments
            scope            = "sub-visualstudio-enterprise"
          }
        ]
        directory_roles = [
          "Cloud application administrator", // Required to be able to create app registrations
          "Directory Writers"                // Required to be able to create SQL AAD groups
        ]
      },
      {
        name                            = "Production"
        subscription                    = "sub-xi-portal-prd"
        connect_to_github               = true
        configure_for_terraform         = true
        requires_terraform_state_access = ["portal-core", "portal-environments"]
        role_assignments = [
          {
            role_definitions = ["Owner", "Key Vault Secrets Officer", "Storage Blob Data Contributor"] // Owner is required to be able to set RBAC role assignments
            scope            = "sub-xi-portal-prd"
          }
        ]
        directory_roles = [
          "Cloud application administrator", // Required to be able to create app registrations
          "Directory Writers"                // Required to be able to create SQL AAD groups
        ]
      }
    ]
  },
  {
    name = "portal-repository-func"
    github = {
      description = "Part of XtremeIdiots Portal solution; repository maintenance and statistics building. Deployed using Terraform and GitHub Actions."
      topics      = ["azure", "terraform", "github-actions", "function-app", "app-insights", "key-vault", "api-subscriptions"]

      add_sonarcloud_secrets = true

      visibility = "public"
    }
    environments = [
      {
        name                            = "Development"
        subscription                    = "sub-visualstudio-enterprise"
        connect_to_github               = true
        configure_for_terraform         = true
        requires_terraform_state_access = ["portal-core", "portal-environments"]
        role_assignments = [
          {
            role_definitions = ["Owner", "Key Vault Secrets Officer", "Storage Blob Data Contributor"] // Owner is required to be able to set RBAC role assignments
            scope            = "sub-visualstudio-enterprise"
          }
        ]
        directory_roles = [
          "Cloud application administrator"
        ]
      },
      {
        name                            = "Production"
        subscription                    = "sub-xi-portal-prd"
        connect_to_github               = true
        configure_for_terraform         = true
        requires_terraform_state_access = ["portal-core", "portal-environments"]
        role_assignments = [
          {
            role_definitions = ["Owner", "Key Vault Secrets Officer", "Storage Blob Data Contributor"] // Owner is required to be able to set RBAC role assignments
            scope            = "sub-xi-portal-prd"
          }
        ]
        directory_roles = [
          "Cloud application administrator"
        ]
      }
    ]
  },
  {
    name = "portal-servers-integration"
    github = {
      description = "Part of XtremeIdiots Portal solution; game server integration via RCON and direct query. Deployed using Bicep and GitHub Actions."
      topics      = ["azure", "bicep", "github-actions", "key-vault", "app-insights", "app-service", "api-subscription", "api-management-api"]

      add_sonarcloud_secrets = true
      add_nuget_environment  = true

      visibility = "public"
    }
    environments = [
      {
        name                       = "Development"
        subscription               = "sub-visualstudio-enterprise"
        connect_to_github          = true
        add_deploy_script_identity = true
        role_assignments = [
          {
            role_definitions = ["Owner", "Key Vault Secrets Officer"] // Owner is required to be able to set RBAC role assignments
            scope            = "sub-visualstudio-enterprise"
          }
        ]
        directory_roles = [
          "Cloud application administrator"
        ]
      },
      {
        name                       = "Production"
        subscription               = "sub-xi-portal-prd"
        connect_to_github          = true
        add_deploy_script_identity = true
        role_assignments = [
          {
            role_definitions = ["Owner", "Key Vault Secrets Officer"] // Owner is required to be able to set RBAC role assignments
            scope            = "sub-xi-portal-prd"
          }
        ]
        directory_roles = [
          "Cloud application administrator"
        ]
      }
    ]
  },
  {
    name = "portal-sync"
    github = {
      description = "Part of XtremeIdiots Portal solution; data synchronization for game servers ban files and other external services. Deployed using Terraform and GitHub Actions."
      topics      = ["azure", "terraform", "github-actions", "function-app", "app-insights", "key-vault", "storage", "api-subscription"]

      add_sonarcloud_secrets = true

      visibility = "public"
    }
    environments = [
      {
        name                            = "Development"
        subscription                    = "sub-visualstudio-enterprise"
        connect_to_github               = true
        configure_for_terraform         = true
        requires_terraform_state_access = ["portal-core", "portal-environments"]
        role_assignments = [
          {
            role_definitions = ["Owner", "Key Vault Secrets Officer", "Storage Blob Data Contributor"] // Owner is required to be able to set RBAC role assignments
            scope            = "sub-visualstudio-enterprise"
          }
        ]
        directory_roles = [
          "Cloud application administrator"
        ]
      },
      {
        name                            = "Production"
        subscription                    = "sub-xi-portal-prd"
        connect_to_github               = true
        configure_for_terraform         = true
        requires_terraform_state_access = ["portal-core", "portal-environments"]
        role_assignments = [
          {
            role_definitions = ["Owner", "Key Vault Secrets Officer", "Storage Blob Data Contributor"] // Owner is required to be able to set RBAC role assignments
            scope            = "sub-xi-portal-prd"
          }
        ]
        directory_roles = [
          "Cloud application administrator"
        ]
      }
    ]
  },
  {
    name = "portal-bots"
    github = {
      description = "Part of XtremeIdiots Portal solution; b3 bots config and instance management. Deployed using Terraform/PowerShell and GitHub Actions/Azure DevOps Pipelines."
      topics      = ["azure", "terraform", "github-actions", "azure-pipelines", "powershell", "key-vault", "app-registration"]

      add_sonarcloud_secrets = true
      add_nuget_environment  = true

      visibility = "public"
    }
    environments = [
      {
        name                            = "Development"
        subscription                    = "sub-visualstudio-enterprise"
        devops_project                  = "XtremeIdiots"
        connect_to_github               = true
        configure_for_terraform         = true
        requires_terraform_state_access = ["portal-core", "portal-environments"]
        role_assignments = [
          {
            role_definitions = ["Owner", "Key Vault Secrets Officer", "Storage Blob Data Contributor"] // Owner is required to be able to set RBAC role assignments
            scope            = "sub-visualstudio-enterprise"
          }
        ]
        directory_roles = [
          "Cloud application administrator"
        ]
      },
      {
        name                            = "Production"
        subscription                    = "sub-xi-portal-prd"
        devops_project                  = "XtremeIdiots"
        connect_to_github               = true
        configure_for_terraform         = true
        requires_terraform_state_access = ["portal-core", "portal-environments"]
        role_assignments = [
          {
            role_definitions = ["Owner", "Key Vault Secrets Officer", "Storage Blob Data Contributor"] // Owner is required to be able to set RBAC role assignments
            scope            = "sub-xi-portal-prd"
          }
        ]
        directory_roles = [
          "Cloud application administrator"
        ]
      }
    ]
  },
  {
    name = "invision-api-client"
    github = {
      description = "Part of XtremeIdiots Portal solution; Invision Community forums integration api client. Published to NuGet.org."
      topics      = ["nuget", "github-actions", "invision-community", "api-client"]

      add_sonarcloud_secrets = true
      add_nuget_environment  = true

      visibility = "public"
    }
  },
  {
    name = "xtremeidiots-portal"
    github = {
      description = "Part of XtremeIdiots Portal solution; legacy repository containing the web app. Deployed using Bicep and Azure DevOps pipelines."
      topics      = ["azure", "bicep", "azure-devops-pipelines", "key-vault", "app-insights", "app-service", "function-app"]

      add_sonarcloud_secrets = true
      add_nuget_environment  = true

      visibility = "public"
    }
    environments = [
      {
        name           = "Development"
        subscription   = "sub-visualstudio-enterprise"
        devops_project = "XtremeIdiots"
        role_assignments = [
          {
            role_definitions = ["Owner", "Key Vault Secrets Officer"] // Owner is required to be able to set RBAC role assignments
            scope            = "sub-visualstudio-enterprise"
          }
        ]
        directory_roles = [
          "Cloud application administrator",
          "Directory Writers" // Required to be able to create SQL AAD groups
        ]
      },
      {
        name           = "Production"
        subscription   = "sub-xi-portal-prd"
        devops_project = "XtremeIdiots"
        role_assignments = [
          {
            role_definitions = ["Owner", "Key Vault Secrets Officer"] // Owner is required to be able to set RBAC role assignments
            scope            = "sub-xi-portal-prd"
          }
        ]
        directory_roles = [
          "Cloud application administrator",
          "Directory Writers" // Required to be able to create SQL AAD groups
        ]
      }
    ]
  },
  {
    name = "cod-demo-reader"
    github = {
      description = "Part of XtremeIdiots Portal solution; library used for reading call of duty Huffman demos. Published to NuGet.org."
      topics      = ["nuget", "github-actions", "invision-community", "api-client"]

      add_sonarcloud_secrets = true
      add_nuget_environment  = true

      visibility = "public"
    }
  },
  {
    name = "demo-manager"
    github = {
      description = "Part of XtremeIdiots Portal solution; demo manager click-once desktop application. Deployed using Bicep and Azure DevOps pipelines."
      topics      = ["desktop", "click-once", "bicep", "storage", "azure-devops-pipelines"]

      add_sonarcloud_secrets = true

      visibility = "public"
    }
    environments = [
      {
        name           = "Production"
        subscription   = "sub-xi-demomanager-prd"
        devops_project = "XtremeIdiots"
        role_assignments = [
          {
            role_definitions = ["Owner"] // Owner is required to be able to set RBAC role assignments
            scope            = "sub-xi-demomanager-prd"
          }
        ]
      }
    ]
  },

  // Geo Location
  {
    name = "geo-location-environments"
    github = {
      description = "GeoLocation environment management including identities, app registrations and permissions. Deployed using Terraform and GitHub Actions."
      topics      = ["azure", "terraform", "github-actions", "app-configuration", "key-vault", "app-registration"]

      visibility = "public"
    }
    environments = [
      {
        name                    = "Development"
        subscription            = "sub-visualstudio-enterprise"
        devops_project          = "Molyneux.IO"
        connect_to_github       = true
        configure_for_terraform = true
        role_assignments = [
          {
            role_definitions = ["Owner", "Key Vault Secrets Officer", "App Configuration Data Owner"] // Owner is required to be able to set RBAC role assignments
            scope            = "sub-visualstudio-enterprise"
          }
        ]
        directory_roles = [
          "Cloud application administrator"
        ]
      },
      {
        name                    = "Production"
        subscription            = "sub-fm-geolocation-prd"
        devops_project          = "Molyneux.IO"
        connect_to_github       = true
        configure_for_terraform = true
        role_assignments = [
          {
            role_definitions = ["Owner", "Key Vault Secrets Officer", "App Configuration Data Owner"] // Owner is required to be able to set RBAC role assignments
            scope            = "sub-fm-geolocation-prd"
          }
        ]
        directory_roles = [
          "Cloud application administrator"
        ]
      }
    ]
  },
  {
    name                      = "geo-location"
    create_dev_center_project = true
    github = {
      description = "GeoLocation service providing IP to location related services. Deployed using Bicep and Azure DevOps pipelines."
      topics      = ["azure", "bicep", "azure-devops-pipelines", "key-vault", "app-insights", "app-service", "api-management-api"]

      add_sonarcloud_secrets = true
      add_nuget_environment  = true

      visibility = "public"
    }
    environments = [
      {
        name                       = "Development"
        subscription               = "sub-visualstudio-enterprise"
        devops_project             = "Molyneux.IO"
        add_deploy_script_identity = true
        connect_to_github          = true
        configure_for_terraform    = true
        role_assignments = [
          {
            role_definitions = ["Owner", "Key Vault Secrets Officer"] // Owner is required to be able to set RBAC role assignments
            scope            = "sub-visualstudio-enterprise"
          }
        ]
        directory_roles = [
          "Cloud application administrator"
        ]
      },
      {
        name                       = "Production"
        subscription               = "sub-fm-geolocation-prd"
        devops_project             = "Molyneux.IO"
        add_deploy_script_identity = true
        connect_to_github          = true
        configure_for_terraform    = true
        role_assignments = [
          {
            role_definitions = ["Owner", "Key Vault Secrets Officer"] // Owner is required to be able to set RBAC role assignments
            scope            = "sub-fm-geolocation-prd"
          }
        ]
        directory_roles = [
          "Cloud application administrator"
        ]
      }
    ]
  },

  // Talk With Tiles
  {
    name = "talkwithtiles"
    github = {
      description = "The TalkWithTiles is a platform that allows users to play online games of Scrabble against each other. Deployed using Terraform and Azure DevOps."
      topics      = ["azure", "terraform", "azue-devops-pipelines", "key-vault", "app-insights", "app-service", "api-management", "api-management-api", "sql-server", "sql-database", "log-analytics"]

      add_sonarcloud_secrets = true

      visibility = "public"
    }
    environments = [
      {
        name                    = "Development"
        subscription            = "sub-visualstudio-enterprise"
        configure_for_terraform = true
        devops_project          = "Molyneux.IO"
        role_assignments = [
          {
            role_definitions = ["Owner", "Key Vault Secrets Officer", "Storage Blob Data Contributor"] // Owner is required to be able to set RBAC role assignments
            scope            = "sub-visualstudio-enterprise"
          }
        ]
        directory_roles = [
          "Cloud application administrator"
        ]
      },
      {
        name                    = "Production"
        subscription            = "sub-talkwithtiles-prd"
        configure_for_terraform = true
        devops_project          = "Molyneux.IO"
        role_assignments = [
          {
            role_definitions = ["Owner", "Key Vault Secrets Officer", "Storage Blob Data Contributor"] // Owner is required to be able to set RBAC role assignments
            scope            = "sub-talkwithtiles-prd"
          }
        ]
        directory_roles = [
          "Cloud application administrator"
        ]
      }
    ]
  },

  // Personal Finances
  {
    name = "personal-finances"
    github = {
      description = "This project is for tracking my personal finances. Deployed using Terraform and GitHub Actions."
      topics      = ["azure", "terraform", "github-actions"]

      add_sonarcloud_secrets = true

      visibility = "public"
    }
    environments = [
      {
        name                    = "Development"
        subscription            = "sub-visualstudio-enterprise"
        connect_to_github       = true
        configure_for_terraform = true
        role_assignments = [
          {
            role_definitions = ["Owner", "Key Vault Secrets Officer", "Storage Blob Data Contributor"] // Owner is required to be able to set RBAC role assignments
            scope            = "sub-visualstudio-enterprise"
          }
        ]
        directory_roles = [
          "Cloud application administrator"
        ]
      },
      {
        name                    = "Production"
        subscription            = "sub-finances-prd"
        connect_to_github       = true
        configure_for_terraform = true
        role_assignments = [
          {
            role_definitions = ["Owner", "Key Vault Secrets Officer", "Storage Blob Data Contributor"] // Owner is required to be able to set RBAC role assignments
            scope            = "sub-finances-prd"
          }
        ]
        directory_roles = [
          "Cloud application administrator"
        ]
      }
    ]
  },

  // Misc Libraries
  {
    name = "api-client-abstractions"
    github = {
      description = "An abstractions library containing common API client functionality for .NET 7. Contains common interfaces, extensions and models for API clients use in my projects. Build and deployed to NuGet.org using GitHub Actions."
      topics      = ["nuget", "github-actions", "api-client", "c-sharp", "dot-net-7"]

      add_sonarcloud_secrets = true
      add_nuget_environment  = true

      visibility = "public"
    }
  },

  // Molyneux.Me
  {
    name = "molyneux-me"
    github = {
      description = "A replacement for my WordPress website. Azure static website using Jekyll and GitHub Actions for deployment."
      topics      = ["azure", "static-website", "jekyll", "github-actions"]

      add_sonarcloud_secrets = true

      visibility = "public"
    }
    environments = [
      {
        name                    = "Development"
        subscription            = "sub-molyneux-me-dev"
        connect_to_github       = true
        configure_for_terraform = true
        role_assignments = [
          {
            role_definitions = ["Owner", "Key Vault Secrets Officer"] // Owner is required to be able to set RBAC role assignments
            scope            = "sub-molyneux-me-dev"
          }
        ]
        }, {
        name                    = "Production"
        subscription            = "sub-molyneux-me-prd"
        connect_to_github       = true
        configure_for_terraform = true
        role_assignments = [
          {
            role_definitions = ["Owner", "Key Vault Secrets Officer"] // Owner is required to be able to set RBAC role assignments
            scope            = "sub-molyneux-me-prd"
          }
        ]
      }
    ]
  },
  {
    name = "skilling-molyneux-me"
    github = {
      description = "Skilling Graph App"
      topics      = ["azure", "asp-net", "github-actions"]

      add_sonarcloud_secrets = true

      visibility = "public"
    }
    environments = [
      {
        name                    = "Development"
        subscription            = "sub-molyneux-me-dev"
        connect_to_github       = true
        configure_for_terraform = false
        role_assignments = [
          {
            role_definitions = ["Owner", "Key Vault Secrets Officer"] // Owner is required to be able to set RBAC role assignments
            scope            = "sub-molyneux-me-dev"
          }
        ]
        directory_roles = [
          "Cloud application administrator"
        ]
      },
      {
        name                    = "Production"
        subscription            = "sub-molyneux-me-prd"
        connect_to_github       = true
        configure_for_terraform = false
        role_assignments = [
          {
            role_definitions = ["Owner", "Key Vault Secrets Officer"] // Owner is required to be able to set RBAC role assignments
            scope            = "sub-molyneux-me-prd"
          }
        ]
        directory_roles = [
          "Cloud application administrator"
        ]
      }
    ]
  },
]
