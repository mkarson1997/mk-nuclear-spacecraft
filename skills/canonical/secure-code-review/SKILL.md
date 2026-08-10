---
name: secure-code-review
description: Review code changes for security defects, privilege boundary violations, secret exposure, injection, unsafe defaults, and fail-open behavior using evidence from the diff and surrounding code.
---

# Secure Code Review

Use for authentication, authorization, network, persistence, CI/CD, deployment, secrets, parsers, file handling, or other security-sensitive changes.

## Review model

1. Identify assets, trust boundaries, attacker-controlled inputs, privileged operations, and externally observable outputs.
2. Review the changed code plus enough surrounding code to understand the real call path.
3. Check authentication and authorization separately. Valid identity never implies valid permission.
4. Check object-level and function-level authorization on every sensitive operation.
5. Trace untrusted data into SQL, shell, templates, filesystem paths, URLs, deserializers, redirects, and logs.
6. Check secrets and tokens for storage, transport, logging, fallback behavior, and accidental client exposure.
7. Check failure behavior. Security controls must fail closed when configuration, verification, parsing, or dependencies fail.
8. Check race conditions and TOCTOU around files, permissions, symlinks, temporary state, locks, and deployment state.
9. Check network egress and dependency execution for unnecessary authority.
10. Confirm tests exercise both allowed behavior and blocked/abusive behavior.

## Finding format

For each real issue provide severity, affected control/path, concrete exploit or failure mode, and the smallest durable fix. Distinguish exploitable findings from hardening suggestions.
