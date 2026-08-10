---
name: documentation-handoff
description: Use this skill when preparing a project handoff, continuation note, runbook, architecture summary, new-conversation reference, or operational documentation. Capture authoritative current state, decisions, exact repositories branches commits, verification evidence, unresolved risks, and next executable steps without mixing historical notes with current requirements.
metadata:
  mk-class: core
  mk-version: "1.0.0"
---

# Documentation Handoff

## Write for continuation

A handoff should let another engineer resume safely without reconstructing the entire conversation.

Include:
- project identity, authoritative repository, and source-of-truth documents;
- current branch or main commit and important merged PRs when relevant;
- architecture and runtime or deployment topology;
- completed work with verification evidence;
- active policies, security gates, and secret or config references without secret values;
- known defects, risks, intentionally deferred items, and failed approaches worth avoiding;
- exact next actions in dependency order;
- commands only when they are current and safe to rerun.

## Source discipline

Separate current requirements from historical context. Mark assumptions and stale snapshots explicitly. Do not promote an old report into an authoritative specification merely because it is detailed.

## Completion

End with a compact resume point: what to inspect first, what must remain disabled or protected, and what success condition unlocks the next phase.
