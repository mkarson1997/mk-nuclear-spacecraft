---
name: architecture-audit
description: Use this skill when evaluating system architecture, major refactors, service boundaries, scalability, data flow, deployment topology, or technical debt before implementation. Map components and trust boundaries, identify coupling and failure domains, test whether complexity is justified, and propose incremental architecture changes with migration and rollback paths.
metadata:
  mk-class: core
  mk-version: "1.0.0"
---

# Architecture Audit

## Map before judging

1. Identify entry points, modules/services, data stores, queues, caches, external providers, clients, and deployment units.
2. Trace important read/write flows and ownership of persistent data.
3. Mark trust boundaries, privileged components, synchronous dependencies, and single points of failure.
4. Separate deliberate architecture from accidental coupling and historical leftovers.
5. Check whether current scale and reliability requirements justify the complexity in use.

## Evaluate

Review cohesion, coupling, dependency direction, state ownership, idempotency, failure isolation, observability, migration safety, testability, and operational burden.

Prefer incremental seams over rewrites. A proposed architecture change must state affected contracts, migration sequence, compatibility window, verification, rollback, and what complexity it removes or deliberately adds.

Return observed architecture, constraints, risks, target state, and prioritized transition steps. Distinguish evidence from inference.
