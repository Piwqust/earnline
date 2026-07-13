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

create table if not exists public.earnline_project_icons (
  id uuid primary key,
  workspace_id text not null default 'your-workspace-id'
    constraint earnline_project_icons_workspace_id_check check (workspace_id = 'your-workspace-id'),
  project_key text not null
    constraint earnline_project_icons_project_key_check check (
      char_length(project_key) between 1 and 40
      and project_key = lower(btrim(project_key))
      and project_key !~ '[[:space:]]{2,}'
    ),
  symbol_name text not null default 'folder'
    constraint earnline_project_icons_symbol_name_check check (symbol_name in (
      'folder', 'briefcase', 'display', 'paintpalette', 'camera', 'video',
      'music.note', 'doc.text', 'megaphone', 'cart', 'globe',
      'wrench.and.screwdriver', 'shippingbox', 'sparkles',
      'chart.line.uptrend.xyaxis', 'building.2'
    )),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint earnline_project_icons_workspace_key_unique unique (workspace_id, project_key)
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

create table if not exists public.earnline_profiles (
  workspace_id text primary key default 'your-workspace-id'
    constraint earnline_profiles_workspace_id_check check (workspace_id = 'your-workspace-id'),
  base_currency_code text not null,
  secondary_currency_code text not null,
  exchange_rate numeric(18, 8) not null constraint earnline_profiles_exchange_rate_check
    check (exchange_rate > 0),
  updated_at timestamptz not null default now(),
  constraint earnline_profiles_currency_pair_check
    check (base_currency_code <> secondary_currency_code)
);

create index if not exists earnline_clients_workspace_updated_idx
  on public.earnline_clients (workspace_id, updated_at desc);

create index if not exists earnline_entries_workspace_updated_idx
  on public.earnline_entries (workspace_id, updated_at desc);

create index if not exists earnline_entries_client_idx
  on public.earnline_entries (client_id);

create index if not exists earnline_headings_workspace_updated_idx
  on public.earnline_headings (workspace_id, updated_at desc);

create index if not exists earnline_project_icons_workspace_updated_idx
  on public.earnline_project_icons (workspace_id, updated_at desc);

create index if not exists earnline_tombstones_workspace_deleted_idx
  on public.earnline_tombstones (workspace_id, deleted_at desc);

alter table public.earnline_clients enable row level security;
alter table public.earnline_entries enable row level security;
alter table public.earnline_headings enable row level security;
alter table public.earnline_project_icons enable row level security;
alter table public.earnline_tombstones enable row level security;
alter table public.earnline_profiles enable row level security;

grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on public.earnline_clients to anon, authenticated;
grant select, insert, update, delete on public.earnline_entries to anon, authenticated;
grant select, insert, update, delete on public.earnline_headings to anon, authenticated;
grant select, insert, update on public.earnline_project_icons to anon, authenticated;
grant select, insert, update, delete on public.earnline_tombstones to anon, authenticated;
revoke all privileges on table public.earnline_profiles from public, anon, authenticated;
grant select, insert, update on public.earnline_profiles to anon, authenticated;

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

drop policy if exists "earnline_project_icons_select_workspace" on public.earnline_project_icons;
create policy "earnline_project_icons_select_workspace"
on public.earnline_project_icons for select
to anon, authenticated
using (workspace_id = 'your-workspace-id');

drop policy if exists "earnline_project_icons_insert_workspace" on public.earnline_project_icons;
create policy "earnline_project_icons_insert_workspace"
on public.earnline_project_icons for insert
to anon, authenticated
with check (workspace_id = 'your-workspace-id');

drop policy if exists "earnline_project_icons_update_workspace" on public.earnline_project_icons;
create policy "earnline_project_icons_update_workspace"
on public.earnline_project_icons for update
to anon, authenticated
using (workspace_id = 'your-workspace-id')
with check (workspace_id = 'your-workspace-id');

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

drop policy if exists "earnline_profiles_select_workspace" on public.earnline_profiles;
create policy "earnline_profiles_select_workspace"
on public.earnline_profiles for select
to anon, authenticated
using (workspace_id = 'your-workspace-id');

drop policy if exists "earnline_profiles_insert_workspace" on public.earnline_profiles;
create policy "earnline_profiles_insert_workspace"
on public.earnline_profiles for insert
to anon, authenticated
with check (workspace_id = 'your-workspace-id');

drop policy if exists "earnline_profiles_update_workspace" on public.earnline_profiles;
create policy "earnline_profiles_update_workspace"
on public.earnline_profiles for update
to anon, authenticated
using (workspace_id = 'your-workspace-id')
with check (workspace_id = 'your-workspace-id');

create or replace function public.earnline_set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists earnline_set_updated_at on public.earnline_profiles;
create trigger earnline_set_updated_at
before insert or update on public.earnline_profiles
for each row execute function public.earnline_set_updated_at();

do $$
declare
  table_name text;
begin
  foreach table_name in array array['earnline_clients', 'earnline_entries', 'earnline_headings', 'earnline_project_icons']
  loop
    execute format('drop trigger if exists earnline_set_updated_at on public.%I', table_name);
    execute format(
      'create trigger earnline_set_updated_at before insert or update on public.%I '
      || 'for each row execute function public.earnline_set_updated_at()', table_name
    );
  end loop;
end $$;

create or replace function public.earnline_set_tombstone_clock()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.deleted_at := now();
  if tg_op = 'INSERT' then new.created_at := now(); else new.created_at := old.created_at; end if;
  return new;
end;
$$;

drop trigger if exists earnline_set_tombstone_clock on public.earnline_tombstones;
create trigger earnline_set_tombstone_clock before insert or update on public.earnline_tombstones
for each row execute function public.earnline_set_tombstone_clock();

do $$
declare
  table_name text;
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
  foreach table_name in array array['earnline_clients', 'earnline_entries', 'earnline_headings', 'earnline_project_icons', 'earnline_tombstones', 'earnline_profiles']
  loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = table_name
    ) then
      execute format('alter publication supabase_realtime add table public.%I', table_name);
    end if;
  end loop;
end $$;
