# Earnline Supabase backend

The timestamped files in `migrations/` are the only schema source of truth.
Apply them in order with the Supabase CLI. There is intentionally no standalone
schema snapshot: the former `earnline_sync_schema.sql` encoded the retired
fixed-workspace anonymous policy and was unsafe to run after the authenticated
workspace cutover.

Production rollout, private owner handoff, Edge Function secrets, backup, and
verification steps live in [`../docs/AUTH_ROLLOUT.md`](../docs/AUTH_ROLLOUT.md).

Functions:

- `earnline-sync`: JWT-protected, RLS-scoped ledger sync with request batching.
- `earnline-pair-device`: public only in the sense that it accepts no existing
  session; a valid ten-minute, one-use pairing token is required before it
  creates a revocable device identity.

Never add a service-role key, OAuth secret, user ID, workspace ID, pairing
token, production row export, or database dump to this directory.
