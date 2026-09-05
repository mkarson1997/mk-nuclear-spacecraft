# Architecture Overview

MK Nuclear Spacecraft is a policy-driven control plane for AI-assisted software engineering. It centralizes governance, agent qualification, reusable skills, project inspection, and verification while keeping individual software products in their own repositories.

## High-level flow

```text
Repository / task
      |
      v
Policies + AGENTS constitution
      |
      v
Registry / routing / qualification
      |
      +-----------------------+
      |                       |
      v                       v
Read-only inspection      Isolated writer path
      |                  (disabled until qualified)
      v                       |
Skills + App Factory          v
planning                worktree + lease + preflight
      |                       |
      +-----------+-----------+
                  |
                  v
          Verification gates
                  |
                  v
             Pull request
                  |
                  v
            Protected main
```

## Main components

### Policies and constitution

`AGENTS.md` defines repository-wide invariants: GitHub as source of truth, protected-main discipline, secret handling, isolated concurrent writers, explicit destructive-operation approval, and verification requirements.

The `policies/` area contains machine- or workflow-oriented controls that narrow what execution layers are permitted to do.

### Agent fleet

`agents/` contains fleet definitions and qualification documentation. Routing modes provide ceilings rather than targets. Writer execution is intentionally fail-closed until trusted-runtime installation, writer canary validation, independent review, and controlled orchestration are qualified.

### Registries

`registry/` stores authoritative declarative inventories such as agent/role capability and skill registration. Runtime decisions should derive from these registries rather than duplicated hard-coded assumptions.

### Skills

`skills/` contains reviewed declarative engineering skills. Skills describe bounded workflows and review behavior; they do not automatically imply network, production, credential, or write privileges.

Packaged or imported skills should include provenance and public-release notes when applicable.

### App Factory

`app-factory/` inspects existing repositories and produces plans/manifests without reinitializing frameworks or silently installing dependencies. Its current qualified layer is inspect/plan oriented. Higher-trust mutation belongs to separately qualified control-plane layers.

### Scripts and hooks

`scripts/` and `hooks/` contain deterministic automation and guardrails. Security-sensitive scripts validate staged content, worktree boundaries, leases, runtime integrity, or execution preconditions before future writer operations.

### MCP and plugins

`mcp/` and `plugins/` separate approved, candidate, and rejected integrations. Presence in the repository does not itself grant runtime authority. External tools remain governed by allowlisting and trust policy.

### Cloud workspace

`cloud-workspace/` is an organizational boundary for workspace patterns and future integrations. It must not contain operator credentials, private runtime state, or production secrets.

### Verification gates

`main` is protected by the `Protect main` repository ruleset (mirrored for reference in [`policies/github/main-ruleset.json`](../policies/github/main-ruleset.json)): linear history, no deletion, no force-push, squash-only merges through pull requests, and required status checks.

Four GitHub Actions workflows in `.github/workflows/` publish `security-gate`, `writer-isolation-gate`, `writer-qualification-gate`, and `app-factory-gate`. The first three are required by the ruleset; `app-factory-gate` runs but is advisory.

A fifth required check, `spacecraft-trust-gate`, is **not** produced by a workflow in this repository. It is published by a separate GitHub App (`MK Spacecraft Trusted Publisher`) that verifies the webhook signature, re-reads the pull request head before and after evaluating it, and refuses to publish a verdict unless a human operator has submitted a signed approval bound to that exact head commit. Approvals are short-lived and single-use.

That controller's source and the operator approval tooling are maintainer-side components and are deliberately **not** part of this repository. The practical consequence is that no change reaches `main` without both the automated gates passing and a fresh human operator signature, and that outside contributors cannot self-approve a merge.

## Trust boundaries

The most important boundaries are:

1. **Repository vs. trusted runtime**: agent-editable source must not silently become trusted executable state.
2. **Coordinator vs. writer**: writers receive bounded assignment/worktree authority, not global repository authority.
3. **Writer vs. protected refs**: no writer is allowed to write directly to protected `main`.
4. **Prompt/config vs. secrets**: credentials must stay outside prompts, Git, logs, screenshots, and generated artifacts.
5. **Declarative skill vs. execution capability**: a skill describes process; it does not inherently receive filesystem, network, credential, or production access.
6. **Project repository vs. control plane**: product code remains in its own repository; this repository carries reusable governance and orchestration logic.

## Current qualification state

The read-only fleet, deterministic routing, worktree lifecycle, writer authority/lease foundations, and multiple verification gates have qualified evidence in the repository.

Project-changing writer execution remains disabled until the remaining trusted-runtime and controlled-writer qualification sequence is completed. Public documentation should preserve this distinction between implemented foundations and enabled autonomous execution.

## Design principle

The control plane follows a fail-closed rule: missing trust evidence should reduce capability rather than silently widen it.
