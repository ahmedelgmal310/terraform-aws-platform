# Security policy

## Reporting a vulnerability

Please report security issues privately through
[GitHub private vulnerability reporting](https://github.com/ahmedelgmal310/terraform-aws-platform/security/advisories/new)
rather than in a public issue. Include the affected module or file, the
impact, and steps to reproduce. You can expect an acknowledgement within a few
days.

## Scope

This repository contains Terraform modules, environment compositions,
policies and CI configuration. Relevant reports include, for example:

- a module default that weakens a documented control (encryption, network
  isolation, IAM scoping, public access);
- a policy in `policies/` that can be bypassed by a plan it should reject;
- a CI workflow that exposes tokens or runs untrusted code with elevated
  permissions.

## Supported versions

Only the `main` branch is maintained.
