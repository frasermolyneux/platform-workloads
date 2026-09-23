# Platform Workloads

[![Build and Test](https://github.com/frasermolyneux/platform-workloads/actions/workflows/build-and-test.yml/badge.svg)](https://github.com/frasermolyneux/platform-workloads/actions/workflows/build-and-test.yml)
[![Code Quality](https://github.com/frasermolyneux/platform-workloads/actions/workflows/codequality.yml/badge.svg)](https://github.com/frasermolyneux/platform-workloads/actions/workflows/codequality.yml)
[![Decommission State Rm](https://github.com/frasermolyneux/platform-workloads/actions/workflows/decommission-state-rm.yml/badge.svg)](https://github.com/frasermolyneux/platform-workloads/actions/workflows/decommission-state-rm.yml)
[![Dependabot Auto-Merge](https://github.com/frasermolyneux/platform-workloads/actions/workflows/dependabot-automerge.yml/badge.svg)](https://github.com/frasermolyneux/platform-workloads/actions/workflows/dependabot-automerge.yml)
[![Deploy Prd](https://github.com/frasermolyneux/platform-workloads/actions/workflows/deploy-prd.yml/badge.svg)](https://github.com/frasermolyneux/platform-workloads/actions/workflows/deploy-prd.yml)
[![Destroy Environment](https://github.com/frasermolyneux/platform-workloads/actions/workflows/destroy-environment.yml/badge.svg)](https://github.com/frasermolyneux/platform-workloads/actions/workflows/destroy-environment.yml)
[![Feature Development](https://github.com/frasermolyneux/platform-workloads/actions/workflows/feature-development.yml/badge.svg)](https://github.com/frasermolyneux/platform-workloads/actions/workflows/feature-development.yml)
[![PR Verify](https://github.com/frasermolyneux/platform-workloads/actions/workflows/pr-verify.yml/badge.svg)](https://github.com/frasermolyneux/platform-workloads/actions/workflows/pr-verify.yml)

## Documentation

* [Architecture Overview](/docs/architecture.md) - End-to-end design and core Terraform patterns.
* [Workload Configuration](/docs/workload-configuration.md) - JSON schema, scope helpers, and examples.
* [Developer Guide](/docs/developer-guide.md) - Local commands, targeting, and troubleshooting tips.
* [Prerequisites](/docs/prerequisites.md) - Required identities, permissions, and environment secrets.
* [Consuming Outputs](/docs/consuming-platform-workloads-outputs.md) - Reading platform-workloads state from downstream stacks.
* [Role Assignments](/docs/role-assignments.md) - RBAC behaviors and ABAC rules.
* [Decommissioning](/docs/decommissioning.md) - State-first removal for managed repositories and policy-only entries.

## Overview

This repository contains a production Terraform catalog for workload infrastructure and repository governance. Definitions with environments can provision Azure AD applications, service principals with OIDC federation, GitHub environments and secrets, Azure DevOps integration, workload-scoped RBAC, and optional Terraform state infrastructure. Managed repository-only definitions omit environments and provision GitHub repository settings and review governance without creating Azure identities or runtime infrastructure. Policy-only entries set `github.manage_repository = false` and reconcile rulesets on an existing repository without taking over its lifecycle. Outputs expose environment-backed resource groups, Terraform backends, service principals, and administrative units for consumption by downstream stacks via remote state.

## Contributing

Please read the [contributing](CONTRIBUTING.md) guidance; this is a learning and development project.

## Security

Please read the [security](SECURITY.md) guidance; I am always open to security feedback through email or opening an issue.
