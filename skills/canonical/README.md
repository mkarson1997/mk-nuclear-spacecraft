# MK Canonical Agent Skills

`skills/canonical/` is the single source of truth for reusable MK Nuclear Spacecraft skills.

Rules:

- Each skill follows the Agent Skills folder model and starts with `SKILL.md`.
- Keep the main skill concise. Put heavy references in `references/` and deterministic helpers in `scripts/` only when needed.
- A skill may teach procedure, but it may not bypass repository policy, GitHub rulesets, hooks, CI, writer isolation, or production approvals.
- Skills from the internet enter quarantine first. They are never installed blindly from marketplaces.
- Scripts, downloads, network access, secret access, destructive operations, licenses, and maintenance status require review before approval.
- Generated client-specific skill trees are outputs. Do not maintain separate hand-edited copies for Claude, Codex, OpenCode, Antigravity, or other clients.

The initial core set intentionally contains no executable helper scripts or external downloads. It is knowledge/procedure only, so the attack surface stays small while the skill system is qualified.
