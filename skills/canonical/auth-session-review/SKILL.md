---
name: auth-session-review
description: Review login, session, token, MFA, password reset, logout, device trust, and recovery flows for secure state transitions and account takeover resistance.
---

# Authentication and Session Review

Use for any identity, login, MFA, reset, recovery, invitation, session, or token change.

## Review sequence

1. Map every authentication state and transition: unauthenticated, pending verification, authenticated, elevated/MFA-verified, locked/revoked, and recovery states.
2. Verify the server is authoritative for security state. UI state must never substitute for persisted server state.
3. Review password/credential verification, rate limits, enumeration resistance, and lockout/abuse handling.
4. Review MFA enrollment, confirmation, recovery, disable/reset, and backup-code behavior. Privileged changes must require appropriate re-authentication.
5. Review session/token issuance, expiry, rotation, revocation, audience/scope, cookie flags, storage, and cross-device behavior.
6. Password reset and account recovery tokens must be single-purpose, bounded, expiring, unpredictable, and invalidated after successful use.
7. Logout/revocation must invalidate the relevant server-side authority, not only clear client UI state.
8. Sensitive operations should require recent authentication or step-up verification where appropriate.
9. Never log passwords, raw tokens, session cookies, reset links, MFA secrets, or recovery material.
10. Test replay, stale session, parallel requests, interrupted enrollment, device loss, privilege downgrade, reset-after-login, and revoked-token cases.

Security transitions must be explicit, persisted, and fail closed.
