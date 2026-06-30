create table if not exists public.earnline_clients (
  id uuid primary key,
  workspace_id text not null default 'your-workspace-id'
    constraint earnline_clients_workspace_id_check check (workspace_id = 'your-workspace-id'),
  name text not null,
  color_hex text not null,
  sort_index integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.earnline_entries (
  id uuid primary key,
  workspace_id text not null default 'your-workspace-id'
    constraint earnline_entries_workspace_id_check check (workspace_id = 'your-workspace-id'),
  client_id uuid not null references public.earnline_clients(id) on delete cascade,
  amount numeric(14, 2) not null,
  currency_code text not null,
  project text,
  task text not null,
  date date not null,
  hold_until date,
  status text not null constraint earnline_entries_status_check
    check (status in ('paid', 'inProgress', 'canceled')),
  sort_index integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.earnline_headings (
  id uuid primary key,
  workspace_id text not null default 'your-workspace-id'
    constraint earnline_headings_workspace_id_check check (workspace_id = 'your-workspace-id'),
  title text not null,
  date date not null,
  sort_index integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.earnline_tombstones (
  id uuid primary key,
  workspace_id text not null default 'your-workspace-id'
    constraint earnline_tombstones_workspace_id_check check (workspace_id = 'your-workspace-id'),
  entity text not null check (entity in ('client', 'entry', 'heading')),
  record_id uuid not null,
  deleted_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create index if not exists earnline_clients_workspace_updated_idx
  on public.earnline_clients (workspace_id, updated_at desc);

create index if not exists earnline_entries_workspace_updated_idx
  on public.earnline_entries (workspace_id, updated_at desc);

create index if not exists earnline_entries_client_idx
  on public.earnline_entries (client_id);

create index if not exists earnline_headings_workspace_updated_idx
  on public.earnline_headings (workspace_id, updated_at desc);

create index if not exists earnline_tombstones_workspace_deleted_idx
  on public.earnline_tombstones (workspace_id, deleted_at desc);

alter table public.earnline_clients enable row level security;
alter table public.earnline_entries enable row level security;
alter table public.earnline_headings enable row level security;
alter table public.earnline_tombstones enable row level security;

grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on public.earnline_clients to anon, authenticated;
grant select, insert, update, delete on public.earnline_entries to anon, authenticated;
grant select, insert, update, delete on public.earnline_headings to anon, authenticated;
grant select, insert, update, delete on public.earnline_tombstones to anon, authenticated;

drop policy if exists "earnline_clients_select_workspace" on public.earnline_clients;
create policy "earnline_clients_select_workspace"
on public.earnline_clients for select
to anon, authenticated
using (workspace_id = 'your-workspace-id');

drop policy if exists "earnline_clients_insert_workspace" on public.earnline_clients;
create policy "earnline_clients_insert_workspace"
on public.earnline_clients for insert
to anon, authenticated
with check (workspace_id = 'your-workspace-id');

drop policy if exists "earnline_clients_update_workspace" on public.earnline_clients;
create policy "earnline_clients_update_workspace"
on public.earnline_clients for update
to anon, authenticated
using (workspace_id = 'your-workspace-id')
with check (workspace_id = 'your-workspace-id');

drop policy if exists "earnline_clients_delete_workspace" on public.earnline_clients;
create policy "earnline_clients_delete_workspace"
on public.earnline_clients for delete
to anon, authenticated
using (workspace_id = 'your-workspace-id');

drop policy if exists "earnline_entries_select_workspace" on public.earnline_entries;
create policy "earnline_entries_select_workspace"
on public.earnline_entries for select
to anon, authenticated
using (workspace_id = 'your-workspace-id');

drop policy if exists "earnline_entries_insert_workspace" on public.earnline_entries;
create policy "earnline_entries_insert_workspace"
on public.earnline_entries for insert
to anon, authenticated
with check (workspace_id = 'your-workspace-id');

drop policy if exists "earnline_entries_update_workspace" on public.earnline_entries;
create policy "earnline_entries_update_workspace"
on public.earnline_entries for update
to anon, authenticated
using (workspace_id = 'your-workspace-id')
with check (workspace_id = 'your-workspace-id');

drop policy if exists "earnline_entries_delete_workspace" on public.earnline_entries;
create policy "earnline_entries_delete_workspace"
on public.earnline_entries for delete
to anon, authenticated
using (workspace_id = 'your-workspace-id');

drop policy if exists "earnline_headings_select_workspace" on public.earnline_headings;
create policy "earnline_headings_select_workspace"
on public.earnline_headings for select
to anon, authenticated
using (workspace_id = 'your-workspace-id');

drop policy if exists "earnline_headings_insert_workspace" on public.earnline_headings;
create policy "earnline_headings_insert_workspace"
on public.earnline_headings for insert
to anon, authenticated
with check (workspace_id = 'your-workspace-id');

drop policy if exists "earnline_headings_update_workspace" on public.earnline_headings;
create policy "earnline_headings_update_workspace"
on public.earnline_headings for update
to anon, authenticated
using (workspace_id = 'your-workspace-id')
with check (workspace_id = 'your-workspace-id');

drop policy if exists "earnline_headings_delete_workspace" on public.earnline_headings;
create policy "earnline_headings_delete_workspace"
on public.earnline_headings for delete
to anon, authenticated
using (workspace_id = 'your-workspace-id');

drop policy if exists "earnline_tombstones_select_workspace" on public.earnline_tombstones;
create policy "earnline_tombstones_select_workspace"
on public.earnline_tombstones for select
to anon, authenticated
using (workspace_id = 'your-workspace-id');

drop policy if exists "earnline_tombstones_insert_workspace" on public.earnline_tombstones;
create policy "earnline_tombstones_insert_workspace"
on public.earnline_tombstones for insert
to anon, authenticated
with check (workspace_id = 'your-workspace-id');

drop policy if exists "earnline_tombstones_update_workspace" on public.earnline_tombstones;
create policy "earnline_tombstones_update_workspace"
on public.earnline_tombstones for update
to anon, authenticated
using (workspace_id = 'your-workspace-id')
with check (workspace_id = 'your-workspace-id');

drop policy if exists "earnline_tombstones_delete_workspace" on public.earnline_tombstones;
create policy "earnline_tombstones_delete_workspace"
on public.earnline_tombstones for delete
to anon, authenticated
using (workspace_id = 'your-workspace-id');
