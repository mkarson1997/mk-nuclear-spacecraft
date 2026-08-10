---
name: dependency-audit
description: Evaluate whether a dependency should be added, retained, upgraded, replaced, or removed using necessity, provenance, maintenance, license, security, transitive risk, and operational cost.
---

# Dependency Audit

Use before adding a package and during dependency/security reviews.

## Decision sequence

1. State the exact capability the dependency provides and whether native/platform code already covers it.
2. Identify the authoritative source, maintainer, license, release cadence, supported runtimes, and package registry identity.
3. Inspect the lockfile impact and transitive dependency expansion.
4. Check known vulnerabilities with the repository's approved scanners.
5. Inspect install/build scripts and unusual network, filesystem, native-code, postinstall, or code-generation behavior.
6. Prefer pinned/locked reproducible versions. Do not delete lockfiles to solve dependency conflicts.
7. Compare at least the practical built-in or existing dependency alternative when the new package adds meaningful authority or maintenance burden.
8. Reject packages with unclear provenance, abandoned maintenance, incompatible licensing, excessive permissions, or unjustified transitive surface.
9. After upgrade, run tests, build, security scans, and affected runtime checks.

## Output

Record decision as APPROVE, KEEP, UPGRADE, REPLACE, REMOVE, or QUARANTINE with the evidence and rollback path.
