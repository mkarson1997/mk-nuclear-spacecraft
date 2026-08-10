---
name: database-migration-safety
description: Use this skill when creating, reviewing, applying, or repairing database schema or data migrations. Protect persistent data with backward-compatible sequencing, explicit lock and transaction expectations, backups, rollback or roll-forward plans, and verification against real application read/write paths.
metadata:
  mk-class: core
  mk-version: "1.0.0"
---

# Database Migration Safety

## Plan the transition

1. Identify current schema and data state, including application versions that may coexist during rollout.
2. Prefer expand-migrate-contract for breaking changes: add compatible structures first, migrate or read both, then remove old structures later.
3. Estimate table size, lock duration, index/build cost, rewrite behavior, and timeout risk.
4. Separate schema migration from large data backfills when operationally safer.
5. Define backup/restore and roll-forward or rollback behavior before production execution.

## Safety rules

Do not use destructive DROP or TRUNCATE shortcuts to repair migration state. Do not silently mark failed migrations as applied. Keep migration history consistent with actual database state. Make tenant, RLS, and authorization implications explicit.

## Verification

Test migration from a representative prior state, application reads and writes after migration, constraints and indexes, recovery procedure, and observability for long-running work.

Return migration sequence, risks, estimated blocking behavior, verification commands, and production go or no-go prerequisites.
