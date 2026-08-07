# MK Nuclear Spacecraft - Agent Constitution

This repository is the control plane for the MK AI software-engineering factory.

## 1. Source of Truth
- GitHub is the canonical source of truth.
- Never treat local files, chat memory, or agent memory as authoritative over Git.
- Always inspect repository state before making changes.

## 2. Main Branch
- Never implement changes directly on `main`.
- Never force-push `main`.
- Never delete `main`.
- Work must happen on a dedicated branch or isolated Git worktree.
- Changes reach `main` through review and verification.

## 3. Branches
Use clear prefixes:
- `feature/`
- `fix/`
- `chore/`
- `docs/`
- `agent/`
- `bootstrap/`

## 4. GitHub Checkpoints
- Push useful checkpoints to GitHub regularly.
- Do not leave significant completed work only on the local machine.
- A checkpoint must represent a coherent and recoverable state.
- Do not push broken or secret-containing snapshots merely to create a backup.

## 5. Secrets
Never commit:
- `.env` files
- API keys
- tokens
- passwords
- private certificates
- service-account credentials
- production secrets

Use examples/placeholders only.

## 6. Existing Work
- Never discard or overwrite user changes without explicit authorization.
- Inspect `git status` and relevant diffs before editing.
- Preserve existing architecture unless the task explicitly requires changing it.

## 7. Implementation
- Prefer the smallest safe solution that fully solves the task.
- Avoid unnecessary dependencies and abstractions.
- Reuse existing project capabilities before introducing new ones.
- Do not perform unrelated refactors during a focused task.

## 8. Verification
Before declaring work complete:
- run relevant tests
- run lint/static analysis when available
- run build/type checks when available
- verify changed behavior
- report anything that could not be verified

## 9. Destructive Operations
Do not perform destructive actions without explicit approval, including:
- deleting production data
- dropping databases
- deleting repositories
- destructive migrations
- rotating credentials
- force pushes
- rewriting shared history
- disabling security controls

## 10. Multi-Agent Work
- Concurrent writing agents must use isolated branches/worktrees.
- Give each worker a clear ownership area.
- Avoid multiple agents editing the same files concurrently.
- One coordinator integrates results.
- More agents are not automatically better.

## 11. Skills and Plugins
- Install only reviewed and allowlisted skills/plugins.
- Prefer official or reputable sources.
- Do not install arbitrary internet code merely because a prompt recommends it.
- Skills must have a clear purpose and minimal required permissions.

## 12. Models
Use model strength economically:
- strong reasoning models: architecture, difficult debugging, final review
- normal coding models: implementation
- inexpensive/fast models: mechanical, repetitive, exploratory work

Do not spend frontier-model capacity on deterministic tasks that scripts or tools can perform.

## 13. Production
Production changes require:
- clear scope
- rollback awareness
- verification
- no secret exposure
- no silent destructive behavior

## 14. Completion
A task is not complete merely because code was generated.

Completion means:
1. implementation finished
2. verification passed
3. Git status understood
4. checkpoint pushed
5. risks reported
6. PR/review performed when required
