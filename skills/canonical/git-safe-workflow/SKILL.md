---
name: git-safe-workflow
description: Safely perform Git work in MK-managed repositories using protected main, isolated task branches or worktrees, explicit verification, and recoverable checkpoints.
---

# Git Safe Workflow

Use this skill whenever a task changes repository state.

## Invariants

1. Treat GitHub as the source of truth.
2. Never develop directly on protected `main`.
3. Never force-push protected refs.
4. Never delete protected refs.
5. Use one task branch/worktree per writer.
6. Preserve unrelated user work.
7. Never stage secrets, private reports, local credentials, generated caches, or environment files.
8. Prefer small coherent checkpoints over giant commits.

## Procedure

1. Inspect repository root, current branch, status, remotes, and upstream divergence.
2. Stop if existing uncommitted work is unrelated or ownership is unclear.
3. Fetch the authoritative remote before starting.
4. Create or enter the dedicated task branch/worktree.
5. Make the smallest safe change.
6. Run project verification and security checks appropriate to the change.
7. Review `git diff` and staged diff before commit.
8. Commit with a precise message.
9. Push the task branch.
10. Merge only through the repository's required PR and CI gates.

## Dangerous operations

Do not run `git push --force`, destructive reset/clean operations, history rewrites, or branch deletion unless a higher-level policy explicitly authorizes the exact operation and recovery state is known.

## Completion evidence

Report branch, commit, verification performed, push state, remaining risks, and PR state. A code change without verified Git state is not complete.
