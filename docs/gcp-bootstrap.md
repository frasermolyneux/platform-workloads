# GCP Bootstrap Guide

This document describes how GCP projects are set up for workloads that need Google Maps API keys.

## Overview

GCP projects and the initial identity federation are bootstrapped manually. The
consuming workload manages its API keys and any resources it declares in Terraform.

Platform-workloads distributes the GCP configuration to consuming repos via GitHub environment variables, using the `gcp` block in workload JSON definitions.

## Architecture

```
Manual Bootstrap (one-time per workload)
├── Create GCP project in Cloud Console
├── Enable APIs (iam, apikeys, maps-backend)
├── Create service account (terraform-platform)
├── Grant IAM roles (serviceAccountAdmin, workloadIdentityPoolAdmin, serviceUsageAdmin, apiKeysAdmin)
├── Create WIF pool + OIDC provider (scoped to platform-workloads + consuming repo)
└── Bind service account to WIF

platform-workloads (this repo)
├── Workload JSON: stores project_id, wif_provider, sa_email
└── gcp-workloads.tf: pushes GCP_PROJECT_ID, GCP_WORKLOAD_IDENTITY_PROVIDER, GCP_SERVICE_ACCOUNT
    as GitHub environment variables to consuming repos

Consuming workload
├── Authenticates to GCP via OIDC
├── Creates google_apikeys_key with URL restrictions
└── Stores key in Azure Key Vault for runtime consumption
```

Current project and identity settings are in the [workload catalog](../terraform/workloads/).
Verify the intended billing account in GCP before linking a new project.

## IAM Roles Granted to Service Accounts

Each `terraform-platform` service account has the following project-level roles:

- `roles/iam.serviceAccountAdmin` — manage service accounts
- `roles/iam.workloadIdentityPoolAdmin` — manage WIF pools
- `roles/serviceusage.serviceUsageAdmin` — enable/disable APIs
- `roles/serviceusage.apiKeysAdmin` — create and manage API keys

## WIF Configuration

Each project has a Workload Identity Pool (`github-actions`) with an OIDC provider (`github-provider`) configured for:

- **Issuer**: `https://token.actions.githubusercontent.com`
- **Attribute mapping**: `google.subject`, `attribute.repository`, `attribute.repository_owner`
- **Attribute condition**: Allows both `frasermolyneux/platform-workloads` and the consuming repo

## Adding a New Workload

To add GCP support for a new workload:

### 1. Create the GCP project

```powershell
gcloud projects create gcp-mx-io-NEW-WORKLOAD --name="GCP New Workload"
gcloud billing projects link gcp-mx-io-NEW-WORKLOAD --billing-account=BILLING_ACCOUNT_ID
```

### 2. Enable APIs

```powershell
gcloud services enable iam.googleapis.com apikeys.googleapis.com maps-backend.googleapis.com --project=gcp-mx-io-NEW-WORKLOAD
```

### 3. Get the project number

```powershell
gcloud projects describe gcp-mx-io-NEW-WORKLOAD --format="value(projectNumber)"
```

### 4. Create service account and grant roles

```powershell
gcloud iam service-accounts create terraform-platform --display-name="Terraform Platform Workloads" --project=gcp-mx-io-NEW-WORKLOAD

gcloud projects add-iam-policy-binding gcp-mx-io-NEW-WORKLOAD --member="serviceAccount:terraform-platform@gcp-mx-io-NEW-WORKLOAD.iam.gserviceaccount.com" --role="roles/iam.serviceAccountAdmin"
gcloud projects add-iam-policy-binding gcp-mx-io-NEW-WORKLOAD --member="serviceAccount:terraform-platform@gcp-mx-io-NEW-WORKLOAD.iam.gserviceaccount.com" --role="roles/iam.workloadIdentityPoolAdmin"
gcloud projects add-iam-policy-binding gcp-mx-io-NEW-WORKLOAD --member="serviceAccount:terraform-platform@gcp-mx-io-NEW-WORKLOAD.iam.gserviceaccount.com" --role="roles/serviceusage.serviceUsageAdmin"
gcloud projects add-iam-policy-binding gcp-mx-io-NEW-WORKLOAD --member="serviceAccount:terraform-platform@gcp-mx-io-NEW-WORKLOAD.iam.gserviceaccount.com" --role="roles/serviceusage.apiKeysAdmin"
```

### 5. Create WIF pool and provider

```powershell
gcloud iam workload-identity-pools create github-actions --location="global" --display-name="GitHub Actions" --project=gcp-mx-io-NEW-WORKLOAD

gcloud iam workload-identity-pools providers create-oidc github-provider --location="global" --workload-identity-pool="github-actions" --issuer-uri="https://token.actions.githubusercontent.com" --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner" --attribute-condition="assertion.repository == 'frasermolyneux/platform-workloads' || assertion.repository == 'frasermolyneux/NEW-WORKLOAD'" --project=gcp-mx-io-NEW-WORKLOAD
```

### 6. Bind service account to WIF

Replace `PROJECT_NUMBER` with the value from step 3:

```powershell
gcloud iam service-accounts add-iam-policy-binding terraform-platform@gcp-mx-io-NEW-WORKLOAD.iam.gserviceaccount.com --role="roles/iam.workloadIdentityUser" --member="principalSet://iam.googleapis.com/projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-actions/attribute.repository/frasermolyneux/platform-workloads" --project=gcp-mx-io-NEW-WORKLOAD

gcloud iam service-accounts add-iam-policy-binding terraform-platform@gcp-mx-io-NEW-WORKLOAD.iam.gserviceaccount.com --role="roles/iam.workloadIdentityUser" --member="principalSet://iam.googleapis.com/projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-actions/attribute.repository/frasermolyneux/NEW-WORKLOAD" --project=gcp-mx-io-NEW-WORKLOAD
```

### 7. Get WIF provider resource name

```powershell
gcloud iam workload-identity-pools providers describe github-provider --workload-identity-pool="github-actions" --location="global" --project=gcp-mx-io-NEW-WORKLOAD --format="value(name)"
```

### 8. Update workload JSON

Merge the relevant fields below into the existing workload JSON in
`terraform/workloads/`; this is a fragment, not a complete workload definition:

```json
{
    "name": "new-workload",
    "gcp": {
        "project_id": "gcp-mx-io-NEW-WORKLOAD",
        "workload_identity_provider": "projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-actions/providers/github-provider",
        "service_account": "terraform-platform@gcp-mx-io-NEW-WORKLOAD.iam.gserviceaccount.com"
    },
    "environments": [
        {
            "name": "Development",
            "subscription": "sub-visualstudio-enterprise",
            "connect_to_github": true,
            "gcp": { "enabled": true }
        }
    ]
}
```

### 9. Deploy platform-workloads

After a reviewed deployment, `gcp-workloads.tf` projects `GCP_PROJECT_ID`,
`GCP_WORKLOAD_IDENTITY_PROVIDER`, and `GCP_SERVICE_ACCOUNT` to each enabled
environment that also has `connect_to_github: true`.
