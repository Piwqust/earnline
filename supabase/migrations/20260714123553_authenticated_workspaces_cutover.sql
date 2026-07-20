-- A4RD-15, phase 2: run only after the private operator handoff documented in
-- docs/AUTH_ROLLOUT.md. This removes the legacy fixed-workspace access model.

do $$
declare
  table_name text;
  existing_policy record;
begin
  foreach table_name in array array[
    'earnline_clients', 'earnline_entries', 'earnline_headings',
    'earnline_tombstones', 'earnline_profiles', 'earnline_project_icons'
  ]
  loop
    execute format('alter table public.%I alter column workspace_id drop default', table_name);
    execute format(
      'alter table public.%I drop constraint if exists %I',
      table_name,
      table_name || '_workspace_id_check'
    );
    for existing_policy in
      select policyname
      from pg_policies
      where schemaname = 'public' and tablename = table_name
    loop
      execute format('drop policy if exists %I on public.%I', existing_policy.policyname, table_name);
    end loop;
  end loop;
end;
$$;

revoke all on table public.earnline_clients from anon;
revoke all on table public.earnline_entries from anon;
revoke all on table public.earnline_headings from anon;
revoke all on table public.earnline_tombstones from anon;
revoke all on table public.earnline_profiles from anon;
revoke all on table public.earnline_project_icons from anon;
revoke all on table public.earnline_workspaces from anon, authenticated;
revoke all on table public.earnline_workspace_members from anon, authenticated;
revoke all on table public.earnline_pairing_tokens from anon, authenticated;

grant usage on schema public to authenticated;
grant select, insert, update, delete on table public.earnline_clients to authenticated;
grant select, insert, update, delete on table public.earnline_entries to authenticated;
grant select, insert, update, delete on table public.earnline_headings to authenticated;
grant select, insert, update, delete on table public.earnline_tombstones to authenticated;
grant select, insert, update on table public.earnline_profiles to authenticated;
grant select, insert, update on table public.earnline_project_icons to authenticated;

-- The RLS policies below execute this predicate as the calling API role.
-- Without this narrowly-scoped grant every otherwise-authorized query fails
-- with `permission denied for function earnline_has_workspace_access`.
grant execute on function public.earnline_has_workspace_access(text) to authenticated;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'earnline_clients', 'earnline_entries', 'earnline_headings',
    'earnline_tombstones', 'earnline_profiles', 'earnline_project_icons'
  ]
  loop
    execute format(
      'create policy %I on public.%I for select to authenticated using ((select public.earnline_has_workspace_access(workspace_id)))',
      table_name || '_select_member', table_name
    );
    execute format(
      'create policy %I on public.%I for insert to authenticated with check ((select public.earnline_has_workspace_access(workspace_id)))',
      table_name || '_insert_member', table_name
    );
    execute format(
      'create policy %I on public.%I for update to authenticated using ((select public.earnline_has_workspace_access(workspace_id))) with check ((select public.earnline_has_workspace_access(workspace_id)))',
      table_name || '_update_member', table_name
    );
  end loop;
end;
$$;

create policy "earnline_clients_delete_member"
on public.earnline_clients for delete to authenticated
using ((select public.earnline_has_workspace_access(workspace_id)));
create policy "earnline_entries_delete_member"
on public.earnline_entries for delete to authenticated
using ((select public.earnline_has_workspace_access(workspace_id)));
create policy "earnline_headings_delete_member"
on public.earnline_headings for delete to authenticated
using ((select public.earnline_has_workspace_access(workspace_id)));
create policy "earnline_tombstones_delete_member"
on public.earnline_tombstones for delete to authenticated
using ((select public.earnline_has_workspace_access(workspace_id)));

-- A row-level membership predicate alone cannot guarantee an Entry's client
-- belongs to the same workspace. The trigger prevents a guessed cross-workspace
-- UUID from becoming a foreign-key relationship.
create or replace function public.earnline_entry_workspace_matches_client()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.earnline_clients client
    where client.id = new.client_id and client.workspace_id = new.workspace_id
  ) then
    raise exception 'Entries must reference a client in the same workspace.';
  end if;
  return new;
end;
$$;

drop trigger if exists earnline_entries_match_workspace on public.earnline_entries;
create trigger earnline_entries_match_workspace
before insert or update of client_id, workspace_id on public.earnline_entries
for each row execute function public.earnline_entry_workspace_matches_client();

revoke all on function public.earnline_entry_workspace_matches_client() from public;
