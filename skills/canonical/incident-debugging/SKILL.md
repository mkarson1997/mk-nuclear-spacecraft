---
name: incident-debugging
description: Use this skill when diagnosing production or staging incidents, intermittent failures, regressions, outages, performance degradation, deployment failures, or unclear error reports. Preserve evidence, establish timeline and blast radius, form testable hypotheses, correlate logs metrics traces and changes, and prefer reversible mitigation before deeper repair.
metadata:
  mk-class: core
  mk-version: "1.0.0"
---

# Incident Debugging

## First establish reality

1. Define symptom, start time, affected users, services or regions, severity, and whether the incident is ongoing.
2. Preserve logs, traces, error IDs, deployment/source versions, and relevant runtime state before destructive cleanup.
3. Compare the last known good state with recent code, configuration, dependency, infrastructure, and data changes.
4. Build explicit hypotheses and seek evidence that can falsify each one.
5. Correlate request IDs, timestamps, service boundaries, queues, and retries rather than reading isolated log lines.

## Mitigation

Prefer bounded, reversible actions: rollback, disable a risky feature, reduce load, isolate a failing dependency, or restore a known-good configuration. Do not make broad production mutations merely to see whether they help.

## Root cause

Distinguish trigger, root cause, contributing factors, detection gap, and recovery gap. Add regression tests, alerts, or runbook improvements that would catch the same class earlier.

Report timeline, evidence, current hypothesis confidence, mitigation, permanent fix, and remaining uncertainty.
