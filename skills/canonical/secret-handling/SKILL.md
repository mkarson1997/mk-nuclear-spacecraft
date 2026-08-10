---
name: secret-handling
description: Use this skill whenever credentials, API keys, tokens, private keys, passwords, cookies, signing material, environment files, or secret stores are involved. Keep secret values out of prompts, logs, Git, artifacts, diffs, screenshots, and generated files; use references and least-privilege secret injection instead.
metadata:
  mk-class: core
  mk-version: "1.0.0"
---

# Secret Handling

## Never expose values unnecessarily

- Do not print, echo, paste, summarize, transform, or commit secret values.
- Refer to secret names and locations, not contents.
- Keep environment files, auth stores, signing keys, cloud credentials, SSH keys, and session tokens outside version control.
- Do not place secrets in command-line arguments when a safer stdin, file descriptor, or secret-store mechanism exists.
- Scrub Authorization headers, cookies, tokens, passwords, and personal data from logs and diagnostics.

## Storage and delivery

Use the approved secret store and the narrowest environment or account scope. Separate development, CI, staging, and production credentials. Prefer short-lived or OIDC credentials where supported.

Credential revocation or rotation can interrupt CI, deployments, integrations, or production traffic. Do not rotate or revoke credentials merely because exposure is suspected. First identify affected systems and dependencies, prepare replacement and recovery steps, and obtain the explicit authorization required by the controlling production/destructive-operation policy.

## Review

When a task touches secrets, verify ignore rules, CI permissions, artifacts, error paths, debug logging, backups, generated configs, and subprocess environment inheritance.

If a secret is discovered in Git history or public output, treat it as potentially compromised: stop further propagation and preserve evidence, identify blast radius, prepare a rotation/revocation and recovery plan, and request explicit authorization before invalidating the credential.

Credential invalidation does not authorize history rewriting or artifact deletion. After approved rotation is verified, prepare any Git-history rewrite, artifact removal, cache purge, or other destructive cleanup as a separate bounded operation and obtain explicit authorization for that exact cleanup before executing it.
