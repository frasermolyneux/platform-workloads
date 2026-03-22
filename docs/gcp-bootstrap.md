# GCP Bootstrap Guide

This document describes how GCP projects are set up for workloads that need Google Maps API keys.

## Overview

GCP projects are created **manually** because the personal GCP account has no organisation, and the Terraform `google_project` resource requires an `org_id` or `folder_id`. Everything inside a project (APIs, service accounts, WIF, API keys) is managed by Terraform in the consuming workloads.

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

Consuming workload (e.g. portal-environments, travel-itinerary, geo-location)
├── Authenticates to GCP via OIDC (google-github-actions/auth@v2)
├── Creates google_apikeys_key with URL restrictions
└── Stores key in Azure Key Vault for runtime consumption
```

## Current GCP Projects

| Workload | GCP Project ID | Project Number | Service Account |
|---|---|---|---|
| portal-environments | `gcp-mx-io-portal-environments` | 298363709846 | `terraform-platform@gcp-mx-io-portal-environments.iam.gserviceaccount.com` |
| travel-itinerary | `gcp-mx-io-travel-itinerary` | 776197093213 | `terraform-platform@gcp-mx-io-travel-itinerary.iam.gserviceaccount.com` |
| geo-location | `gcp-mx-io-geo-location` | 518912876139 | `terraform-platform@gcp-mx-io-geo-location.iam.gserviceaccount.com` |

Billing account: `01A0B4-212B1F-46CD27`

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
gcloud billing projects link gcp-mx-io-NEW-WORKLOAD --billing-account=01A0B4-212B1F-46CD27
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

Add the `gcp` block to the workload JSON in `terraform/workloads/`:

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
            "gcp": { "enabled": true }
        }
    ]
}
```

### 9. Deploy platform-workloads

This pushes `GCP_PROJECT_ID`, `GCP_WORKLOAD_IDENTITY_PROVIDER`, and `GCP_SERVICE_ACCOUNT` as GitHub environment variables to the consuming repo.
