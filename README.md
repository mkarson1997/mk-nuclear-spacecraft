# MK Nuclear Spacecraft ☢️🛸

**Policy-driven AI software-engineering control plane for safe multi-agent development.**

[![Security Gate](https://github.com/mkarson1997/mk-nuclear-spacecraft/actions/workflows/security-gate.yml/badge.svg)](https://github.com/mkarson1997/mk-nuclear-spacecraft/actions/workflows/security-gate.yml)
[![Writer Isolation](https://github.com/mkarson1997/mk-nuclear-spacecraft/actions/workflows/writer-isolation-gate.yml/badge.svg)](https://github.com/mkarson1997/mk-nuclear-spacecraft/actions/workflows/writer-isolation-gate.yml)
[![Writer Qualification](https://github.com/mkarson1997/mk-nuclear-spacecraft/actions/workflows/writer-qualification-gate.yml/badge.svg)](https://github.com/mkarson1997/mk-nuclear-spacecraft/actions/workflows/writer-qualification-gate.yml)
[![App Factory](https://github.com/mkarson1997/mk-nuclear-spacecraft/actions/workflows/app-factory-gate.yml/badge.svg)](https://github.com/mkarson1997/mk-nuclear-spacecraft/actions/workflows/app-factory-gate.yml)

MK Nuclear Spacecraft centralizes reusable engineering governance around AI coding tools while keeping application repositories independent. It treats agents as bounded engineering workers, not as automatically trusted operators.

## What lives here

- repository-wide engineering and security policies;
- deterministic agent-fleet routing and qualification rules;
- isolated writer worktree/lease foundations;
- reusable declarative engineering skills;
- App Factory project detection and safe bootstrap planning;
- hooks and Git/GitHub guardrails;
- MCP/plugin review boundaries;
- verification scripts and GitHub Actions gates;
- architecture, qualification, and operational documentation.

Individual software products stay in their own GitHub repositories.

## Why this project exists

AI coding tools are useful, but scaling them from one interactive assistant to several concurrent workers creates new failure modes: overlapping edits, unsafe branch writes, hidden credential exposure, unreviewed plugins, unclear authority, and unverifiable completion claims.

This repository makes those boundaries explicit and increasingly mechanical.

## Safety model

Core invariants include:

1. GitHub is the canonical source of truth.
2. No agent writes directly to protected `main`.
3. Concurrent writers require isolated worktrees and ownership leases.
4. A fleet role never implies production access.
5. Secrets stay outside Git, prompts, logs, screenshots, and generated artifacts.
6. Skills/plugins require review and allowlisting.
7. Destructive or production-impacting actions require explicit authorization.
8. Missing trust evidence reduces capability instead of silently widening it.

See [`AGENTS.md`](AGENTS.md) and [`SECURITY.md`](SECURITY.md).

## Architecture

```text
Task / repository
      |
      v
Policies + registries
      |
      v
Routing + qualification
      |
      +--------------------+
      |                    |
      v                    v
Read-only planning     Isolated writer path
      |                (qualification-gated)
      v                    |
Skills / App Factory       v
      |              worktree + lease + preflight
      +----------+---------+
                 |
                 v
          verification gates
                 |
                 v
            pull request
                 |
                 v
            protected main
```

For trust boundaries and component responsibilities, see [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Current qualification state

The repository has evidence for:

- deterministic SIMPLE / NORMAL / POWER / NUCLEAR routing plans;
- read-only fleet qualification;
- isolated Git worktree lifecycle and path containment;
- writer engine/role authorization and ownership leases;
- trusted-runtime integrity/preflight foundations;
- security, writer-isolation, writer-qualification, and App Factory CI gates;
- a required `spacecraft-trust-gate` check that only reports success after a human operator signs an approval bound to the exact commit being merged.

**Project-changing autonomous writer execution remains disabled by policy** until the remaining trusted-runtime installation, controlled writer canary, independent review, and orchestration qualification steps pass.

That distinction is intentional: implemented safety infrastructure is not presented as enabled autonomous production capability.

See [`agents/FLEET.md`](agents/FLEET.md) for the qualification sequence.

## Repository map

| Area | Responsibility |
| --- | --- |
| `policies/` | execution and safety policy |
| `registry/` | declarative agent/skill authority |
| `agents/` | fleet routing and qualification |
| `skills/` | reviewed reusable engineering workflows |
| `app-factory/` | repository inspection and safe bootstrap planning |
| `scripts/` | deterministic automation and verification |
| `hooks/` | guardrail integration points |
| `mcp/` | approved/candidate/rejected MCP boundaries |
| `plugins/` | reviewed plugin boundary |
| `cloud-workspace/` | workspace patterns without operator secrets |
| `.github/workflows/` | CI trust and qualification gates |
| `policies/github/` | reference copy of the enforced `main` branch ruleset |

## Open-source boundary

Repository-authored material is released under the MIT License. External tools, services, SDKs, packaged artifacts, and trademarks retain their own terms. See [`LICENSE`](LICENSE) and [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).

Never commit live credentials, customer data, private deployment identifiers, runtime secrets, or operator-specific state.

## Project principle

> **Capability follows evidence.**

The goal is not to launch the largest possible agent swarm. The goal is to use the smallest effective fleet while preserving isolation, reviewability, recoverability, and proof that the work actually passed its gates.
