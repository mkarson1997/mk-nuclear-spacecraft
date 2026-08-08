# MK Security Baseline

## Default posture

Deny or ask before granting authority.

## Git

- Never develop directly on main.
- Never force-push protected branches.
- Never delete protected branches.
- Writing agents use branches or isolated worktrees.
- Important recoverable checkpoints are pushed to GitHub.

## Secrets

Secrets must never be committed to repositories.

Allowed repository artifact:

.env.example

Actual secrets belong only in approved secret stores.

## Agent authority

Agents receive the minimum permissions required for their role.

Security auditors are read-only by default.

No general-purpose agent receives automatic production write access.

## Plugins and MCP

Unknown plugins and MCP servers are quarantined.

Approval requires review of:

- source
- maintainer
- version
- license
- scripts
- dependencies
- network access
- secret access
- filesystem access
- write authority
- maintenance activity

## Security tooling

Baseline security stack:

1. Gitleaks
2. Trivy
3. Semgrep
4. zizmor

Additional security tools are activated by project risk.

## Production

Development infrastructure and production infrastructure remain separated.

Destructive production operations always require explicit approval.

## Principle

Skills advise.
Hooks enforce.
Scanners detect.
CI gates.
GitHub preserves truth.
