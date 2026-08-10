---
name: api-security-review
description: Review HTTP, RPC, GraphQL, and mobile-backend APIs for object/function authorization, authentication, validation, resource abuse, SSRF, inventory, unsafe upstream consumption, and secure error behavior.
---

# API Security Review

Use for new or changed API endpoints and backend integrations.

## Checklist

1. Enumerate routes, methods, authentication requirements, caller roles, object identifiers, and state changes.
2. Verify object-level authorization for every resource lookup or mutation. Never trust an ID merely because it is syntactically valid.
3. Verify function-level authorization for administrative, bulk, export, moderation, billing, and privileged operations.
4. Review authentication token validation, expiry, audience/issuer rules, revocation expectations, and failure behavior.
5. Define strict input schemas, size limits, pagination limits, upload limits, and bounded expensive operations.
6. Prevent mass assignment/object-property overposting by allowlisting writable fields.
7. Review URLs and callbacks for SSRF, redirect abuse, DNS/IP edge cases, and unsafe internal network access.
8. Treat upstream APIs and webhooks as untrusted inputs; verify signatures and parse defensively.
9. Avoid sensitive data in errors and logs. Use stable error codes and correlation IDs where appropriate.
10. Keep an accurate route/API inventory and remove stale versions intentionally.
11. Test abusive cases: foreign object IDs, privilege escalation, missing/expired auth, duplicate/replay requests, oversized inputs, rate abuse, and malformed upstream data.

Prefer mechanical tests for authorization boundaries over narrative confidence.
