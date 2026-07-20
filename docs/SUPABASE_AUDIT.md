# Supabase audit

This is an operator audit record for the iPhone-first Earnline product, not the
public project overview. Start with the [project README](../README.md) for the
app or the [documentation map](README.md) for related runbooks.

Verified on 2026-07-17 against both the empty staging project and the live
production project. This document contains no project refs, user identifiers,
workspace identifiers, URLs, keys, or private ledger values.

## Decision

Earnline does not need a database rewrite. The ledger model is appropriate for
an offline-first personal product: SwiftData and IndexedDB remain local sources
of truth, while Postgres stores shared clients, entries, headings, tombstones,
profile settings, and project icons. The required refactor was the
authorization and operations boundary, and that cutover is complete.

## Live production snapshot

- One permanent OAuth owner and one owned workspace.
- No paired devices, expired test workspaces, or outstanding pairing tokens
  after verification.
- 46 private application rows across the six synchronized tables.
- PostgreSQL 17.6; database size about 12.5 MB.
- Anonymous table grants removed; 22 workspace-scoped RLS policies active.
- Anonymous Auth and new public sign-ups disabled. Email/password is disabled;
  Google, GitHub, and Apple providers remain configured.
- `earnline-sync` and `earnline-pair-device` active.
- Daily pairing-artifact cleanup registered with `pg_cron`.
- No managed backup was listed for the Free project. Pre- and post-cutover REST
  row exports plus Auth, migration, schema, policy, function, grant, and backup
  metadata snapshots were created locally under the ignored `.local-backups/`
  directory.

## Authorization and data flow

1. A permanent owner signs in with OAuth.
2. Supabase Auth issues a user JWT. The app never receives an OAuth secret or a
   service-role key.
3. RLS derives the caller from `auth.uid()` and resolves a single workspace
   membership. Clients never choose a workspace ID for authorization.
4. The web client calls `earnline-sync` with the user JWT. The function validates
   the JWT and performs all ledger operations through a caller-scoped client, so
   RLS remains the final boundary.
5. The owner creates a ten-minute, one-use pairing token. The public pairing
   function validates it before allocating a server-marked device identity,
   redeems it atomically, and returns a revocable session.
6. Revoking or disconnecting a device deletes its Auth identity, membership,
   refresh tokens, and redeemed one-time token. Old access tokens no longer pass
   workspace authorization.

## Verification completed

- Fresh staging database migrated from empty through all tracked migrations.
- Public key received no rows from any synchronized table.
- Sync without a user JWT returned `401`; invalid pairing returned `403`.
- Owner access returned `200` for every synchronized table.
- Full owner -> pairing token -> device -> sync -> device list -> revoke flow
  passed on staging and production; the revoked token returned `403`.
- Production retained all 46 rows through the cutover.
- Web: 82 tests, TypeScript check, and production build passed.
- iOS: unit and UI suites passed; the Paired Devices surface was exercised in
  the simulator and checked through the accessibility hierarchy.
- Edge Functions pass Deno type checking; repository secret scan and
  `git diff --check` pass.

## Free-plan capacity

The current Supabase Free quotas include 50,000 monthly active Auth users,
500 MB of database size per project, 5 GB egress, 500,000 Edge Function
invocations, two active Free projects, 200 peak Realtime connections, and two
million Realtime messages. Free projects can pause after a week of inactivity
and do not include the Pro plan's seven-day daily backups. Confirm current
values before a launch:

- <https://supabase.com/docs/guides/platform/billing-on-supabase>
- <https://supabase.com/pricing>

For Earnline's intended one-owner model the Free plan has ample capacity. The
database currently uses roughly 2.5% of the 500 MB limit. The first practical
scaling constraint for a multi-user product would be Edge Function invocations,
not Auth MAU: a clean visible web sync currently takes about four function
invocations and polls every two minutes. That is approximately 28,800
invocations per month for a browser visible eight hours every day, so 500,000
invocations represents roughly 17 such continuously active browser sessions
before writes, retries, iOS traffic, or multi-page datasets. At one visible hour
per day it is roughly 138 sessions. These are planning estimates, not guaranteed
user limits.

## Operating rules

- Make schema changes only through tracked migrations.
- Apply every migration to staging from an empty database and run both security
  verifiers before production.
- Export rows and control-plane metadata before every production migration.
- Use Table Editor for inspection, not routine manual writes.
- Review Auth users, function errors/latency, database size, egress, MAU, and
  function invocation usage weekly. Investigate at 60% and plan a change at 80%.
- Keep production origins in Supabase secrets/deployment configuration, never in
  source. Add a deployed web origin only when that deployment exists.
- Move to Pro before Supabase becomes business-critical: managed daily backups,
  longer logs, and avoidance of Free-project pausing matter more here than the
  raw MAU allowance.
- Before turning Earnline into a public multi-user SaaS, replace fixed polling
  with change-driven sync or a longer adaptive interval, load-test RLS and sync,
  add per-workspace quotas, and define account deletion/export flows.

Detailed deployment and recurring-operation steps live in
`AUTH_ROLLOUT.md` and `SUPABASE_OPERATIONS.md`.
