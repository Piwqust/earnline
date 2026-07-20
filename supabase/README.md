# earn›line backend

This is sync and device-pairing infrastructure for the **iPhone-first**
Earnline product. It is not a user-facing app surface: the native iPhone app is
the primary experience, and the optional web companion follows the same private
workspace contract.

## What belongs here

- Timestamped migrations in `migrations/`, applied in order.
- `earnline-sync`, which synchronizes a caller's permitted ledger data.
- `earnline-pair-device`, which exchanges a valid one-time pairing code for a
  revocable device identity.

The apps remain local-first; this backend is used only when a private workspace
is connected. Never commit service-role keys, OAuth secrets, pairing codes,
production records, user IDs, or workspace identifiers here.

Start with [the documentation map](../docs/README.md) for the operator runbook,
security audit, and recurring checks.
