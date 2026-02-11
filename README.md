# Platform Workloads

[![Code Quality](https://github.com/frasermolyneux/platform-workloads/actions/workflows/codequality.yml/badge.svg)](https://github.com/frasermolyneux/platform-workloads/actions/workflows/codequality.yml)
[![Feature Development](https://github.com/frasermolyneux/platform-workloads/actions/workflows/feature-development.yml/badge.svg)](https://github.com/frasermolyneux/platform-workloads/actions/workflows/feature-development.yml)
[![Release to Production](https://github.com/frasermolyneux/platform-workloads/actions/workflows/release-to-production.yml/badge.svg)](https://github.com/frasermolyneux/platform-workloads/actions/workflows/release-to-production.yml)
[![Dependabot Automerge](https://github.com/frasermolyneux/platform-workloads/actions/workflows/dependabot-automerge.yml/badge.svg)](https://github.com/frasermolyneux/platform-workloads/actions/workflows/dependabot-automerge.yml)

## Documentation
* [Architecture Overview](/docs/architecture.md) - End-to-end design and core Terraform patterns.
* [Workload Configuration](/docs/workload-configuration.md) - JSON schema, scope helpers, and examples.
* [Developer Guide](/docs/developer-guide.md) - Local commands, targeting, and troubleshooting tips.
* [Prerequisites](/docs/prerequisites.md) - Required identities, permissions, and environment secrets.
* [Consuming Outputs](/docs/consuming-platform-workloads-outputs.md) - Reading platform-workloads state from downstream stacks.
* [Role Assignments](/docs/role-assignments.md) - RBAC behaviors and ABAC rules.

## Overview
Terraform automation that turns JSON workload definitions into Azure AD applications/service principals with OIDC, GitHub repositories/environments/secrets, Azure DevOps service connections/environments/variable groups, and workload-scoped RBAC. Optional feature gates create per-workload Terraform state resource groups/storage and deploy-script managed identities. Scope resolution supports subscription aliases, raw ARM IDs, and workload helpers, while outputs expose resource groups, Terraform backends, and administrative units for downstream consumers.

## Contributing
Please read the [contributing](CONTRIBUTING.md) guidance; this is a learning and development project.

## Security
Please read the [security](SECURITY.md) guidance; I am always open to security feedback through email or opening an issue.
