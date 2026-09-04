# Earnline 1.0 release checklist

This checklist is the release boundary for the current repository. A green
local build is not a substitute for staging, signed-device, or production
evidence.

## Repository gates — implemented

- [x] SwiftData V3 guest import includes `MonthReview` and reports migration
      failures instead of silently returning an empty summary.
- [x] Project-symbol catalog is checked against Swift, SQL, and Edge sources.
- [x] iOS sync uses server-timestamp keyset pagination and bounded upsert
      chunks; pushed rows are marked clean only when their edit stamp is still
      unchanged.
- [x] Tombstones use a server trigger for authoritative deletion timestamps;
      local sync compares tombstones with the last observed row version.
- [x] Client, entry, heading, currency, project-icon, and month-review payloads
      are validated on pull and in the Edge contract.
- [x] Profile edits fail closed when the remote profile changed since the last
      observed baseline.
- [x] Pairing redemption is retryable for the same request identifier.
- [x] Auth sessions use project-scoped Keychain storage with surfaced storage
      errors; OAuth callback route validation is exact.
- [x] JSON full backup/export/import is versioned, validated, merge-only, and
      covered by round-trip/idempotency/orphan tests. CSV remains an exchange
      format, not a backup.
- [x] Release builds reject missing HTTPS production configuration, privacy URL,
      secret Supabase keys, and service-role keys.
- [x] XcodeGen drift, SwiftLint, backend syntax/contract checks, web tests,
      typecheck, and build are represented in CI.

## Evidence still required before 1.0 GO

- [ ] Apply and verify all current migrations in a disposable staging project,
      including `earnline_month_reviews`, project-icon constraints, sync
      invariants, and tombstone trigger grants.
- [ ] Run authenticated staging E2E with two owners, two workspaces, paired
      devices, revoked sessions, cross-workspace probes, realtime/offline
      recovery, concurrent edits/deletes, 1001-row payloads, and lost-response
      pairing/sync cases.
- [ ] Create a real server backup, restore it into a clean staging project, and
      compare row counts, IDs, canonical row hashes, foreign keys, and financial
      totals. Keep backup credentials server-only.
- [ ] Run the full unit/UI/AppStoreRelease plans on iOS 26.4.1 and iOS 27.0.
- [ ] Build a signed Release archive, verify it with
      `codesign --verify --deep --strict`, install it on a physical iPhone, and
      exercise auth, Keychain/app lock, camera/QR pairing, CSV, offline, relaunch,
      and recovery flows.
- [ ] Recheck App Store privacy answers, privacy/support URLs, entitlements,
      provisioning, and the final production Supabase configuration before
      upload.

## Current verdict

The repository is ready for the staging phase, not for an App Store 1.0 GO.
Production data and infrastructure were not changed by this work.
