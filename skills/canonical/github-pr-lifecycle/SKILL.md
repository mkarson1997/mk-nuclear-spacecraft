---
name: github-pr-lifecycle
description: Drive a GitHub pull request from branch creation through CI, review, thread resolution, and guarded merge without bypassing repository rules.
---

# GitHub PR Lifecycle

Use for any change that must enter a protected branch.

## Procedure

1. Confirm the task branch is pushed and based on the intended target branch.
2. Open a focused PR with summary, safety state, verification evidence, and explicit non-goals.
3. Inspect every required status check on the current PR head. Never rely on checks from an older commit.
4. Treat review comments as findings, not decoration. Reproduce or reason about each finding before changing code.
5. Fix valid findings on the same branch, push, and wait for checks to re-run on the new head.
6. Resolve review threads only after the underlying issue is fixed or a documented, bounded disposition is justified.
7. Re-fetch PR metadata immediately before merge.
8. Merge only when required checks are green, review requirements are satisfied, threads are resolved, and the expected head SHA still matches.
9. Prefer squash when repository policy requires linear history.
10. After merge, verify the target branch contains the expected commit and no unexpected follow-up changes occurred.

## Fail closed

Do not merge if the PR head moved unexpectedly, a required check is pending/failed/missing, a security finding remains Critical/High, or the ruleset state is ambiguous.
