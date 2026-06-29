alter table public.earnline_clients drop constraint if exists earnline_clients_user_id_fkey;
alter table public.earnline_entries drop constraint if exists earnline_entries_user_id_fkey;
alter table public.earnline_headings drop constraint if exists earnline_headings_user_id_fkey;
alter table public.earnline_tombstones drop constraint if exists earnline_tombstones_user_id_fkey;

alter table public.earnline_clients alter column user_id drop not null;
alter table public.earnline_entries alter column user_id drop not null;
alter table public.earnline_headings alter column user_id drop not null;
alter table public.earnline_tombstones alter column user_id drop not null;

alter table public.earnline_clients add column if not exists workspace_id text not null default 'earnline-personal';
alter table public.earnline_entries add column if not exists workspace_id text not null default 'earnline-personal';
alter table public.earnline_headings add column if not exists workspace_id text not null default 'earnline-personal';
alter table public.earnline_tombstones add column if not exists workspace_id text not null default 'earnline-personal';

alter table public.earnline_clients drop constraint if exists earnline_clients_workspace_id_check;
alter table public.earnline_entries drop constraint if exists earnline_entries_workspace_id_check;
alter table public.earnline_headings drop constraint if exists earnline_headings_workspace_id_check;
alter table public.earnline_tombstones drop constraint if exists earnline_tombstones_workspace_id_check;

alter table public.earnline_clients add constraint earnline_clients_workspace_id_check check (workspace_id = 'earnline-personal');
alter table public.earnline_entries add constraint earnline_entries_workspace_id_check check (workspace_id = 'earnline-personal');
alter table public.earnline_headings add constraint earnline_headings_workspace_id_check check (workspace_id = 'earnline-personal');
alter table public.earnline_tombstones add constraint earnline_tombstones_workspace_id_check check (workspace_id = 'earnline-personal');

create index if not exists earnline_clients_workspace_updated_idx
  on public.earnline_clients (workspace_id, updated_at desc);
create index if not exists earnline_entries_workspace_updated_idx
  on public.earnline_entries (workspace_id, updated_at desc);
create index if not exists earnline_headings_workspace_updated_idx
  on public.earnline_headings (workspace_id, updated_at desc);
create index if not exists earnline_tombstones_workspace_deleted_idx
  on public.earnline_tombstones (workspace_id, deleted_at desc);

revoke all privileges on table public.earnline_clients from anon, authenticated;
revoke all privileges on table public.earnline_entries from anon, authenticated;
revoke all privileges on table public.earnline_headings from anon, authenticated;
revoke all privileges on table public.earnline_tombstones from anon, authenticated;

grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on table public.earnline_clients to anon, authenticated;
grant select, insert, update, delete on table public.earnline_entries to anon, authenticated;
grant select, insert, update, delete on table public.earnline_headings to anon, authenticated;
grant select, insert, update, delete on table public.earnline_tombstones to anon, authenticated;

drop policy if exists "earnline_clients_select_own" on public.earnline_clients;
drop policy if exists "earnline_clients_insert_own" on public.earnline_clients;
drop policy if exists "earnline_clients_update_own" on public.earnline_clients;
drop policy if exists "earnline_clients_delete_own" on public.earnline_clients;
drop policy if exists "earnline_clients_select_workspace" on public.earnline_clients;
drop policy if exists "earnline_clients_insert_workspace" on public.earnline_clients;
drop policy if exists "earnline_clients_update_workspace" on public.earnline_clients;
drop policy if exists "earnline_clients_delete_workspace" on public.earnline_clients;

create policy "earnline_clients_select_workspace"
on public.earnline_clients for select
to anon, authenticated
using (workspace_id = 'earnline-personal');
create policy "earnline_clients_insert_workspace"
on public.earnline_clients for insert
to anon, authenticated
with check (workspace_id = 'earnline-personal');
create policy "earnline_clients_update_workspace"
on public.earnline_clients for update
to anon, authenticated
using (workspace_id = 'earnline-personal')
with check (workspace_id = 'earnline-personal');
create policy "earnline_clients_delete_workspace"
on public.earnline_clients for delete
to anon, authenticated
using (workspace_id = 'earnline-personal');

drop policy if exists "earnline_entries_select_own" on public.earnline_entries;
drop policy if exists "earnline_entries_insert_own" on public.earnline_entries;
drop policy if exists "earnline_entries_update_own" on public.earnline_entries;
drop policy if exists "earnline_entries_delete_own" on public.earnline_entries;
drop policy if exists "earnline_entries_select_workspace" on public.earnline_entries;
drop policy if exists "earnline_entries_insert_workspace" on public.earnline_entries;
drop policy if exists "earnline_entries_update_workspace" on public.earnline_entries;
drop policy if exists "earnline_entries_delete_workspace" on public.earnline_entries;

create policy "earnline_entries_select_workspace"
on public.earnline_entries for select
to anon, authenticated
using (workspace_id = 'earnline-personal');
create policy "earnline_entries_insert_workspace"
on public.earnline_entries for insert
to anon, authenticated
with check (workspace_id = 'earnline-personal');
create policy "earnline_entries_update_workspace"
on public.earnline_entries for update
to anon, authenticated
using (workspace_id = 'earnline-personal')
with check (workspace_id = 'earnline-personal');
create policy "earnline_entries_delete_workspace"
on public.earnline_entries for delete
to anon, authenticated
using (workspace_id = 'earnline-personal');

drop policy if exists "earnline_headings_select_own" on public.earnline_headings;
drop policy if exists "earnline_headings_insert_own" on public.earnline_headings;
drop policy if exists "earnline_headings_update_own" on public.earnline_headings;
drop policy if exists "earnline_headings_delete_own" on public.earnline_headings;
drop policy if exists "earnline_headings_select_workspace" on public.earnline_headings;
drop policy if exists "earnline_headings_insert_workspace" on public.earnline_headings;
drop policy if exists "earnline_headings_update_workspace" on public.earnline_headings;
drop policy if exists "earnline_headings_delete_workspace" on public.earnline_headings;

create policy "earnline_headings_select_workspace"
on public.earnline_headings for select
to anon, authenticated
using (workspace_id = 'earnline-personal');
create policy "earnline_headings_insert_workspace"
on public.earnline_headings for insert
to anon, authenticated
with check (workspace_id = 'earnline-personal');
create policy "earnline_headings_update_workspace"
on public.earnline_headings for update
to anon, authenticated
using (workspace_id = 'earnline-personal')
with check (workspace_id = 'earnline-personal');
create policy "earnline_headings_delete_workspace"
on public.earnline_headings for delete
to anon, authenticated
using (workspace_id = 'earnline-personal');

drop policy if exists "earnline_tombstones_select_own" on public.earnline_tombstones;
drop policy if exists "earnline_tombstones_insert_own" on public.earnline_tombstones;
drop policy if exists "earnline_tombstones_update_own" on public.earnline_tombstones;
drop policy if exists "earnline_tombstones_delete_own" on public.earnline_tombstones;
drop policy if exists "earnline_tombstones_select_workspace" on public.earnline_tombstones;
drop policy if exists "earnline_tombstones_insert_workspace" on public.earnline_tombstones;
drop policy if exists "earnline_tombstones_update_workspace" on public.earnline_tombstones;
drop policy if exists "earnline_tombstones_delete_workspace" on public.earnline_tombstones;

create policy "earnline_tombstones_select_workspace"
on public.earnline_tombstones for select
to anon, authenticated
using (workspace_id = 'earnline-personal');
create policy "earnline_tombstones_insert_workspace"
on public.earnline_tombstones for insert
to anon, authenticated
with check (workspace_id = 'earnline-personal');
create policy "earnline_tombstones_update_workspace"
on public.earnline_tombstones for update
to anon, authenticated
using (workspace_id = 'earnline-personal')
with check (workspace_id = 'earnline-personal');
create policy "earnline_tombstones_delete_workspace"
on public.earnline_tombstones for delete
to anon, authenticated
using (workspace_id = 'earnline-personal');
