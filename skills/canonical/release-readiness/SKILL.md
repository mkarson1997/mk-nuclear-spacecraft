---
name: release-readiness
description: Decide whether a build is ready to release using source integrity, tests, security, migrations, configuration, observability, rollback, artifacts, and operational evidence.
---

# Release Readiness

Use before staging promotion, production deployment, mobile store submission, or a major public release.

## Gate

1. Confirm the release source commit is known, reviewed, merged through required gates, and reproducible from the authoritative repository.
2. Confirm required tests, build, lint/static analysis, security scans, and dependency checks are green on that source.
3. Review database migrations for ordering, compatibility, rollback/forward-fix strategy, data volume, locking, and backup requirements.
4. Verify environment/configuration requirements without exposing secrets. Missing production configuration must fail closed.
5. Generate or validate release artifacts from the approved pipeline. Record checksums/SBOM/signing/provenance when the project requires them.
6. Confirm logging, error tracking, health/readiness signals, and key operational dashboards/alerts are sufficient to detect a bad release.
7. Define rollback or containment steps before deployment, including who/what triggers them.
8. Run critical end-to-end flows in staging or the safest equivalent environment.
9. Review known residual risks and explicitly decide whether they are release blockers.
10. Use staged rollout where supported for high-impact changes.

## Verdict

Return GO, CONDITIONAL GO, or NO-GO with evidence. Never label a release ready solely because compilation succeeded.
