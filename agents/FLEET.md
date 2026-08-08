# MK Agent Fleet

Phase 2 qualification begins with a deterministic fleet registry and router.

## Current state

The fleet is in qualification mode.

Project execution is disabled by policy until writer isolation, trusted runtime boundaries, assignment leases, and controlled orchestration pass dedicated qualification.

The read-only Fleet Core qualification layer is complete:

- all six registered CLI engines are available;
- SIMPLE, NORMAL, POWER, and NUCLEAR routing plans are deterministic;
- worktree create/status/remove lifecycle passed controlled smoke testing;
- worktree path containment rejects traversal-style names;
- Grok completed an independent read-only qualification review without repository mutation;
- Codex completed an independent read-only qualification review in a native read-only sandbox using structured completion gating;
- verification remains green and project execution remains disabled.

## Engines

- Claude Code: commander, planner, architect, reviewer
- Codex CLI: implementer, reviewer, test engineer
- Antigravity CLI: orchestrator and parallel coordinator
- OpenCode: flexible worker and fallback worker
- Grok CLI: researcher and independent reviewer
- Aider: Git-native reserve implementer

## Modes

- SIMPLE: up to 2 agent slots
- NORMAL: up to 5 agent slots
- POWER: up to 10 agent slots
- NUCLEAR: up to 25 agent slots

Agent ceilings are safety limits, not targets. The router should use the smallest effective fleet.

## Safety invariants

1. No agent writes directly to `main`.
2. Concurrent writers require isolated Git worktrees.
3. One coordinator integrates results.
4. Security review should be independent from the primary implementer.
5. Production access is never implied by a fleet role.
6. NUCLEAR mode is reserved for genuinely divisible work graphs.
7. Qualification commands may inspect availability and produce plans, but must not launch project-changing agents.

## Writer enablement blockers

Writer agents must remain disabled until all of the following controls are mechanically enforced:

1. A trusted runtime/launcher is executed outside agent-editable project worktrees and resolves only allowlisted engine binaries.
2. Every writer is bound to one registered worktree and one `agent-work/*` branch.
3. Engine and role combinations are validated against one authoritative role schema.
4. Worktree ownership is persisted as an atomic assignment/lease containing engine, role, branch, path, coordinator, and lifecycle state.
5. Concurrent writer access is locked so one active writer owns one leased worktree.
6. Writer sandbox, filesystem, network, credential, and protected-ref boundaries are enforced independently of prompt instructions.
7. Writer processes cannot push directly to protected branches and do not receive production credentials by default.
8. Routing emits a machine-readable execution plan and fails closed when required isolation or reviewer independence cannot be satisfied.

## Qualification sequence

1. Fleet status and version probe. **PASS**
2. Deterministic routing plan for all four modes. **PASS**
3. Worktree lifecycle and path containment. **PASS**
4. Read-only agent launch boundary and semantic completion guard. **PASS**
5. Independent Grok and Codex review handoff. **PASS**
6. Writer ownership, lease, and concurrency controls. **PENDING**
7. Controlled writer qualification inside this repository. **PENDING**
8. Controlled orchestration test inside this repository. **PENDING**
9. Enable project execution only after all writer gates pass. **LOCKED**
