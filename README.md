# Platform Workloads

[![Build and Test](https://github.com/frasermolyneux/platform-workloads/actions/workflows/build-and-test.yml/badge.svg)](https://github.com/frasermolyneux/platform-workloads/actions/workflows/build-and-test.yml)
[![Code Quality](https://github.com/frasermolyneux/platform-workloads/actions/workflows/codequality.yml/badge.svg)](https://github.com/frasermolyneux/platform-workloads/actions/workflows/codequality.yml)
[![PR Verify](https://github.com/frasermolyneux/platform-workloads/actions/workflows/pr-verify.yml/badge.svg)](https://github.com/frasermolyneux/platform-workloads/actions/workflows/pr-verify.yml)
[![Feature Development](https://github.com/frasermolyneux/platform-workloads/actions/workflows/feature-development.yml/badge.svg)](https://github.com/frasermolyneux/platform-workloads/actions/workflows/feature-development.yml)
[![Deploy Dev](https://github.com/frasermolyneux/platform-workloads/actions/workflows/deploy-dev.yml/badge.svg)](https://github.com/frasermolyneux/platform-workloads/actions/workflows/deploy-dev.yml)
[![Deploy Prd](https://github.com/frasermolyneux/platform-workloads/actions/workflows/deploy-prd.yml/badge.svg)](https://github.com/frasermolyneux/platform-workloads/actions/workflows/deploy-prd.yml)
[![Destroy Environment](https://github.com/frasermolyneux/platform-workloads/actions/workflows/destroy-environment.yml/badge.svg)](https://github.com/frasermolyneux/platform-workloads/actions/workflows/destroy-environment.yml)
[![Dependabot Automerge](https://github.com/frasermolyneux/platform-workloads/actions/workflows/dependabot-automerge.yml/badge.svg)](https://github.com/frasermolyneux/platform-workloads/actions/workflows/dependabot-automerge.yml)
[![Copilot Setup Steps](https://github.com/frasermolyneux/platform-workloads/actions/workflows/copilot-setup-steps.yml/badge.svg)](https://github.com/frasermolyneux/platform-workloads/actions/workflows/copilot-setup-steps.yml)

## Documentation

* [Architecture Overview](/docs/architecture.md) - End-to-end design and core Terraform patterns.
* [Workload Configuration](/docs/workload-configuration.md) - JSON schema, scope helpers, and examples.
* [Developer Guide](/docs/developer-guide.md) - Local commands, targeting, and troubleshooting tips.
* [Prerequisites](/docs/prerequisites.md) - Required identities, permissions, and environment secrets.
* [Consuming Outputs](/docs/consuming-platform-workloads-outputs.md) - Reading platform-workloads state from downstream stacks.
* [Role Assignments](/docs/role-assignments.md) - RBAC behaviors and ABAC rules.

## Overview

This repository contains a Terraform stack that transforms JSON workload definitions into fully provisioned Azure AD applications, service principals with OIDC federation, GitHub repositories with environments and secrets, and Azure DevOps service connections, environments, and variable groups. It manages workload-scoped RBAC role assignments with ABAC-conditioned delegation, supporting subscription aliases, raw ARM IDs, and workload-based scope helpers for flexible scope resolution. Optional feature gates (`connect_to_github`, `connect_to_devops`, `configure_for_terraform`, `add_deploy_script_identity`) enable per-workload Terraform state storage, deploy-script managed identities, and CI/CD integration. Outputs expose resource groups, Terraform backends, service principals, and administrative units for consumption by downstream stacks via remote state.

## Contributing

Please read the [contributing](CONTRIBUTING.md) guidance; this is a learning and development project.

## Security

Please read the [security](SECURITY.md) guidance; I am always open to security feedback through email or opening an issue.
