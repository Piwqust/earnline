# earn›line backend

This directory contains the shared Supabase database migrations and the small
functions that support private workspace sync and device pairing.

## What belongs here

- Timestamped migrations in `migrations/`, applied in order.
- `earnline-sync`, which synchronizes a caller's permitted ledger data.
- `earnline-pair-device`, which exchanges a valid one-time pairing code for a
  revocable device identity.

The iOS and web apps remain local-first; this backend is used only when a
private workspace is connected. Never commit service-role keys, OAuth secrets,
pairing codes, production records, user IDs, or workspace identifiers here.
