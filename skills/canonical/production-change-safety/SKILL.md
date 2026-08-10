---
name: production-change-safety
description: Prepare and execute production-affecting changes with least privilege, explicit blast radius, backups, observability, staged rollout, rollback, and no silent destructive actions.
---

# Production Change Safety

Use whenever a task can modify production infrastructure, data, credentials, releases, traffic, or customer-visible state.

## Rules

1. Production access is never implied by implementation permission.
2. Identify exact target environment, service, data set, blast radius, and irreversible operations before execution.
3. Prefer read-only inspection first.
4. Verify backups/snapshots or a tested recovery path before destructive data/schema/infrastructure changes.
5. Separate build/review from deployment authority where the platform permits it.
6. Use least-privilege credentials scoped to the exact operation and environment.
7. Never print or persist secrets in logs, artifacts, prompts, shell history, or repository files.
8. Use staging/canary/gradual rollout when available.
9. Watch health, errors, latency, business signals, queues, and database behavior during and after the change.
10. Stop and contain when observed behavior leaves the predeclared safe envelope.
11. Execute rollback or forward-fix from a prepared procedure, not improvisation under outage pressure.
12. Record source commit, operator/automation identity, time, verification, and final state.

Any destructive command requires explicit authorization from a higher-level policy or human gate. A production change is incomplete until post-change verification passes.
