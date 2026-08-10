---
name: repo-audit
description: Produce a grounded repository audit covering architecture, runtime paths, tests, security, CI/CD, dependencies, documentation, and operational risks before major work.
---

# Repository Audit

Use before large refactors, inherited projects, migrations, or release rescue work.

## Audit sequence

1. Identify the repository's actual entrypoints, packages/apps, build systems, lockfiles, configuration, and deployment targets.
2. Map runtime architecture and data flow from code, not README claims alone.
3. Locate authentication, authorization, persistence, network boundaries, background jobs, file/media handling, and external integrations.
4. Inspect test layout and determine which critical flows have executable coverage.
5. Inspect CI/CD workflows, deployment scripts, secrets expectations, branch rules, and rollback mechanisms.
6. Inventory dependencies and note stale, unpinned, abandoned, or unusually privileged packages.
7. Search for TODO/FIXME/stubs/mock-only paths, disabled gates, fallback credentials, and silent error handling.
8. Compare documentation against implementation and mark stale claims.
9. Separate findings into confirmed defects, architectural debt, missing evidence, and optional improvements.

## Output

Return a prioritized audit with severity, evidence path, user/business impact, recommended action, and verification method. Do not call something broken solely because a feature is absent unless requirements say it must exist.
