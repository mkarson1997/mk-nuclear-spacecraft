---
name: test-strategy
description: Design the smallest high-value test portfolio for a change using unit, component/widget, integration, contract, and critical end-to-end tests with explicit negative cases.
---

# Test Strategy

Use when planning implementation, fixing regressions, or preparing a release.

## Procedure

1. Identify the behavior that can regress, the trust boundaries involved, and the cheapest test layer that can prove each behavior.
2. Put deterministic logic in fast unit tests.
3. Put UI/component behavior in component or widget tests without unnecessary full-stack setup.
4. Use integration/contract tests for database, API, queue, filesystem, and service boundaries.
5. Reserve end-to-end tests for a small set of business-critical journeys.
6. Add negative tests for authorization, invalid input, retries, timeouts, partial failure, duplicate/replay behavior, and destructive-operation guards where relevant.
7. Reproduce a bug with a failing regression test before or alongside the fix when practical.
8. Avoid tests that merely assert implementation details with no user or contract value.
9. Make flaky tests visible and fix or quarantine them deliberately; never normalize rerunning until green.
10. Ensure CI runs the right subset automatically and heavier suites have a documented trigger.

## Completion

State what is proven, what remains untested, and why the remaining risk is acceptable. A passing test suite is evidence only for the behavior it actually exercises.
