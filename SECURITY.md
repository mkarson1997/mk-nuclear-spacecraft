# Security Policy

MK Nuclear Spacecraft is a policy-driven software-engineering control plane. Security defects in its trust boundaries, writer isolation, secret handling, protected-ref checks, package validation, or qualification gates can affect every project that consumes it.

## Supported branch

Security fixes target the current `main` branch unless a release-specific policy states otherwise.

## Reporting a vulnerability

Please do not publish credentials, private keys, tokens, exploit payloads, or sensitive environment details in a public issue.

Prefer GitHub private vulnerability reporting or a private security advisory when available. If that channel is unavailable, contact the maintainer through the GitHub profile and share only enough information to establish a private reporting channel.

A useful report includes:

- affected component and commit;
- expected and observed security boundary;
- minimal reproduction steps;
- realistic impact and prerequisites;
- whether a secret, production system, or external account may already be exposed.

## Security invariants

The repository is designed around these defaults:

- no direct agent writes to protected `main`;
- concurrent writers require isolated worktrees and ownership leases;
- production access is never implied by an agent role;
- secrets must not enter Git, prompts, logs, generated artifacts, or screenshots;
- skills/plugins require review and allowlisting;
- destructive or production-impacting actions require explicit authorization;
- qualification and writer execution fail closed when required trust evidence is missing.

## Secret exposure

If a real credential is discovered, stop further propagation. Treat it as potentially compromised, identify its blast radius, and prepare rotation/revocation and recovery steps. Credential invalidation and Git-history rewriting are separate potentially disruptive operations and should be authorized and executed deliberately.

## Public-release boundary

Examples may contain variable names and obvious placeholders. They must not contain live credentials, customer data, private deployment identifiers, or operator-specific runtime state.
