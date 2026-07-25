-- Audit follow-up (docs/AUDIT-2026-07.md, findings S1 and S3).
--
-- Supabase installs default privileges that grant EXECUTE on every new function
-- in `public` to `anon` and `authenticated`. A `revoke ... from public` does not
-- remove those role-specific grants, so
-- 20260714123553_authenticated_workspaces_cutover.sql:118 left the entry/client
-- workspace trigger function callable over the REST API as
-- `/rest/v1/rpc/earnline_entry_workspace_matches_client`.
--
-- Calling it is harmless in practice — plpgsql refuses to run a trigger function
-- outside a trigger context — but a trigger helper has no business being in the
-- API surface, and the same default applies to every non-RPC function added
-- here in future. Revoke explicitly from all three grantees.

revoke execute on function public.earnline_entry_workspace_matches_client()
  from anon, authenticated, public;

-- The row-clock triggers are in the same category: they exist only to be fired
-- by a trigger, never to be invoked by a client.
do $$
declare
  routine_name text;
begin
  foreach routine_name in array array[
    'earnline_set_updated_at', 'earnline_set_tombstone_clock'
  ]
  loop
    if exists (
      select 1 from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = routine_name
    ) then
      execute format(
        'revoke execute on function public.%I() from anon, authenticated, public',
        routine_name
      );
    end if;
  end loop;
end $$;

-- Covering indexes for the two foreign keys the performance advisor flagged.
-- The table is small, but an unindexed FK turns every parent delete into a
-- sequential scan, and device revocation deletes through both of these.
create index if not exists earnline_pairing_tokens_workspace_idx
  on public.earnline_pairing_tokens (workspace_id);
create index if not exists earnline_pairing_tokens_redeemed_by_idx
  on public.earnline_pairing_tokens (redeemed_by);

-- Documentation only, so the security advisor's `rls_enabled_no_policy` INFO on
-- these three tables is not "fixed" later by someone adding policies to silence
-- it. RLS is enabled and *no policy exists on purpose*: the cutover migration
-- revokes every privilege on them from `anon` and `authenticated`
-- (20260714123553_authenticated_workspaces_cutover.sql:37-39), so they are
-- reachable only through `SECURITY DEFINER` functions that enforce membership
-- themselves. Adding a policy would widen access, not narrow it.
comment on table public.earnline_workspaces is
  'Workspace registry. No RLS policy by design: all privileges are revoked from anon/authenticated, so access is only ever through SECURITY DEFINER RPCs. See docs/AUDIT-2026-07.md (S3).';
comment on table public.earnline_workspace_members is
  'Membership registry. No RLS policy by design — see earnline_workspaces. Read via earnline_has_workspace_access() / earnline_current_workspace().';
comment on table public.earnline_pairing_tokens is
  'Short-lived device pairing tokens. No RLS policy by design — issued and redeemed only through SECURITY DEFINER RPCs and the earnline-pair-device edge function.';
