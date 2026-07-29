# Supabase operations

This is an operator runbook for the iPhone-first Earnline product. For the app
itself, start with the [project README](../README.md); use the
[documentation map](README.md) to navigate the technical material.

Earnline is one personal workspace owned by one permanent account. Additional
phones and browsers receive revocable device identities. It is not a public
multi-tenant signup product.

## Before every schema or function deployment

1. Export the current rows with `scripts/backup-supabase-rest.mjs`. It requires
   a server-only backup access token; the publishable key is never used as a
   Bearer credential.
2. Create a full Dashboard backup or run `pg_dump` with a short-lived database
   connection string. The REST export does not include Auth users, grants,
   policies, functions, triggers, or migration history.
3. Apply the same migrations to a separate staging project from an empty
   database and run the read-only verifier against staging.
4. Keep the old iOS and web clients available until the new functions and RLS
   checks pass.

## Clean restore proof

Do this only against an empty, isolated staging project. It reads every
restored row but does not write anything.

1. Restore the full database backup into the clean staging project using the
   Supabase Dashboard backup flow or `pg_restore`. Do not use the REST export
   as a replacement for an Auth/schema backup.
2. In a terminal, set short-lived credentials only for that shell, then run:

   ```bash
   SUPABASE_RESTORE_URL='https://staging-project.supabase.co' \
   SUPABASE_RESTORE_PUBLISHABLE_KEY='staging-publishable-key' \
   SUPABASE_RESTORE_ACCESS_TOKEN='server-only-staging-backup-token' \
   node scripts/verify-supabase-backup-restore.mjs .local-backups/supabase-rest-YYYY-MM-DDTHH-MM-SSZ
   ```

   The command checks the manifest hashes, every table row and ID, entry-to-
   client foreign keys, and money totals by currency. It prints counts and
   totals, never ledger rows or credentials.
3. Delete the temporary staging project or restore it to its empty baseline
   after the proof. This prevents backup data from becoming a second live
   workspace.

## Read-only security verification

```bash
set -a
source web/.env.local
set +a
node scripts/verify-supabase-security.mjs
```

For owner checks, provide a short-lived access token only in the current shell:

```bash
SUPABASE_OWNER_ACCESS_TOKEN='short-lived-token' node scripts/verify-supabase-security.mjs
```

The token must never be added to `.env`, shell history, logs, screenshots, or
the repository.

## Weekly checks

- Dashboard **Reports / Database**: database size and largest tables.
- Dashboard **Auth / Users**: no unexpected permanent accounts and no orphaned
  device identities.
- Dashboard **Edge Functions**: error rate, invocation count, and latency for
  both functions.
- Dashboard **Logs**: repeated `invalid or expired` pairing attempts, 401/403
  sync spikes, or RLS errors.
- Dashboard **Billing / Usage**: database, egress, Realtime, MAU, and Edge
  Function usage. Investigate at 60%, plan an upgrade or optimization at 80%.
- Confirm that the latest full backup can be downloaded and that its date is
  recorded outside the repository.

Useful read-only SQL:

```sql
select pg_size_pretty(pg_database_size(current_database()));

select relname,
       pg_size_pretty(pg_total_relation_size(relid)) as total_size
from pg_catalog.pg_statio_user_tables
order by pg_total_relation_size(relid) desc;

select schemaname, tablename, policyname, roles, cmd
from pg_policies
where schemaname = 'public' and tablename like 'earnline_%'
order by tablename, policyname;

select role, count(*)
from public.earnline_workspace_members
group by role;
```

## Device lifecycle

- Pairing tokens expire after ten minutes and are one-use.
- A valid token is checked before a device Auth identity is created.
- Owners can list and revoke devices from Settings.
- Revocation deletes the device Auth identity, invalidating refresh tokens and
  cascading its membership.
- Signing out on a paired device deletes that device identity and membership;
  reconnecting always requires a new one-time code.
- A daily `pg_cron` job removes expired tokens and orphaned device identities.

## Tombstones

Tombstones remain intentionally unpruned. A personal device may be offline for
months, so age-based deletion could resurrect removed ledger rows. Introduce a
per-device acknowledgement watermark before adding retention.
