# Runtime GitHub Apps

`github.runtime_apps` declares dedicated workload identities separately from the
existing `github.github_app` shared CI automation integration. Each declaration
specifies the owning account, repository permissions, exact installation repository
selection, environment and workload Key Vault secret name.

GitHub requires a person to approve App registration and installation. The manifest
bootstrap automates the configuration, key retrieval, Key Vault storage, installation
verification and non-secret catalog registration around those approvals. Terraform
does not create the App or read its private key.

## Bootstrap

Use Python 3.10 or later, Azure CLI and an authenticated browser on the same machine.
Run `az login` and select the subscription containing the workload's runtime vault.
The signed-in Azure identity needs to list vaults and read/write secrets in the
target vault (for example, Key Vault Secrets Officer), and **Storage Blob Data
Contributor** access to the existing production Terraform backend container.
Storage commands use Entra login, never account keys.

From the repository root:

```powershell
python -m pip install -r scripts\requirements-github-apps.txt
python scripts\bootstrap_github_app.py --workload platform-status-web --app status-incidents
```

1. Open the local bootstrap link and approve the preconfigured App registration.
   Sign in as the declared owner. The status App requests **Issues: read/write**,
   implicit repository metadata access, no events, no active webhook and no OAuth.
2. Follow the installation link and select **Only select repositories**, then
   **status-pages**. Do not select all repositories.
3. Review the resulting workload JSON change. Normal reviewed Terraform deployment
   publishes `GH_STATUS_INCIDENTS_APP_ID`, `GH_STATUS_INCIDENTS_INSTALLATION_ID` and
   `GH_STATUS_INCIDENTS_APP_SLUG` in the owning workload repository.

The key is stored directly in the unique vault tagged with the declaration's
`Workload`, `Environment` and `Purpose=workload-secrets`. It is not printed, written
locally, put in Actions secrets or passed through Terraform state. The registration
code is exchanged in memory. Temporary installation-verification tokens are revoked.
`--no-browser` prints the links instead of opening them automatically.

All bootstraps share an exclusive lease on `runtime-github-app-bootstrap.lock` in
the existing backend container. The lease covers catalog reads, approvals, key
storage and registration updates across processes and machines. Only one bootstrap
can run at a time; a second attempt fails before registering an App. The Terraform
state blob itself is never locked or modified. No new Azure resources are required.
The lease is checked before writes and released on normal completion, errors and
keyboard cancellation. Vault credentials are refreshed after browser approval.

The workload owner must separately review the read-only container secret mount,
host allowlist and runtime App settings. Registration is not a runtime deployment.
The service must mint short-lived installation tokens restricted to its configured
repository and required permissions, not use a broad installation token.

## Resume and recovery

Rerunning the command reuses the owned Key Vault key and checks the App's actual
owner, permissions, events and exact installed repositories. It does not rotate an
existing key or register a replacement for a known App. If installation times out,
the key is already safe in Key Vault and the catalog contains a partial registration;
rerun bootstrap after completing installation.

If a bootstrap process terminates without releasing its lease, do not start another
bootstrap until its operator confirms that the original process has stopped.
Then explicitly break only `runtime-github-app-bootstrap.lock` using
`az storage blob lease break --account-name <backend-account> --container-name <backend-container> --blob-name runtime-github-app-bootstrap.lock --auth-mode login`.
Never break the Terraform state lease as part of App-bootstrap recovery.

Unknown, disabled, expiring or soft-deleted keys require explicit recovery.
Correct an overbroad installation selection in GitHub and rerun. A key that was
deleted should be recovered from Key Vault, not replaced by rerunning registration.
If registration succeeds but key storage fails, generate a replacement key through
the App's GitHub settings and install it in the declared vault with the expected
ownership tags; do not paste key material into issues, chat or catalog JSON.

Declarations and registration metadata are source controlled. Changes to permissions,
repositories or key ownership require review and re-verification; modifying the
catalog alone does not change the GitHub App registration. Removing a declaration
does not uninstall or delete the App or purge its key.

## Validation

```powershell
python -m unittest discover -s scripts -p 'test_*.py'
terraform -chdir=terraform test '-var-file=tfvars\prd.tfvars' '-filter=tests\runtime-github-apps.tftest.hcl'
```

The bootstrap follows GitHub's
[App manifest registration flow](https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest).
