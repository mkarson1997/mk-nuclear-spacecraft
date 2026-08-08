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

The Writer Safety foundation is also now mechanically qualified without launching a writer agent:

- `registry/agent-fleet.json` is the authoritative engine/role permission source;
- invalid engine-role pairs and read-only roles are rejected for writer worktrees;
- every writer worktree receives an atomic persistent lease containing engine, role, branch, path, coordinator, and lease identity;
- worktree lease creation/removal is protected by an exclusive filesystem lock;
- writer worktree creation and lease cleanup passed positive/negative smoke tests;
- a separate execution policy keeps both project writer execution and writer qualification execution disabled;
- trusted runtime installation is permitted only from clean, synchronized `main` matching remote `main`;
- the writer runtime refuses to execute from inside the repository or an agent-editable worktree;
- trusted runtime files and manifest are SHA256 validated outside the repository;
- writer preflight validates lease ownership, branch namespace, worktree identity, engine/role authorization, clean Git state, and executable type before any future writer launch.

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
7. Qualification commands may inspect availability and produce plans, but must not launch project-changing agents unless the dedicated writer-qualification policy is explicitly enabled after trusted-runtime installation.

## Writer enablement blockers

Writer agents must remain disabled until all remaining controls are mechanically enforced and qualified:

1. The trusted runtime must be installed from merged `main`, activated outside project worktrees, and pass its integrity check.
2. A writer qualification launcher must use the trusted runtime only, bind to one active lease/worktree, and enforce the exact qualification path allowlist.
3. Writer filesystem and protected-ref checks must detect and block mutations outside the allowed canary path.
4. Writer execution must remain unable to commit, push, or access production credentials during qualification.
5. A different model family must independently review the qualification diff before any broader writer capability is enabled.
6. Routing must emit a machine-readable execution plan and fail closed when required isolation, leases, engine readiness, or reviewer independence cannot be satisfied.
7. Controlled orchestration must pass before project writer execution can be enabled.

## Qualification sequence

1. Fleet status and version probe. **PASS**
2. Deterministic routing plan for all four modes. **PASS**
3. Worktree lifecycle and path containment. **PASS**
4. Read-only agent launch boundary and semantic completion guard. **PASS**
5. Independent Grok and Codex review handoff. **PASS**
6. Writer engine/role authority, ownership lease, concurrency lock, and trusted-runtime foundation. **PASS**
7. Install trusted runtime from merged `main` and qualify external preflight. **PENDING**
8. Controlled Codex writer canary in one leased worktree with exact-path mutation allowlist. **PENDING**
9. Independent review of the writer canary diff. **PENDING**
10. Controlled orchestration test inside this repository. **PENDING**
11. Enable project execution only after all writer gates pass. **LOCKED**
