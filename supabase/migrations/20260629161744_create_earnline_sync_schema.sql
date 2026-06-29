create table if not exists public.earnline_clients (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  color_hex text not null,
  sort_index integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.earnline_entries (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  client_id uuid not null references public.earnline_clients(id) on delete cascade,
  amount numeric(14, 2) not null,
  currency_code text not null,
  project text,
  task text not null,
  date date not null,
  hold_until date,
  status text not null check (status in ('logged', 'inProgress', 'paid')),
  sort_index integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.earnline_headings (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  date date not null,
  sort_index integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.earnline_tombstones (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  entity text not null check (entity in ('client', 'entry', 'heading')),
  record_id uuid not null,
  deleted_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create index if not exists earnline_clients_user_updated_idx
  on public.earnline_clients (user_id, updated_at desc);

create index if not exists earnline_entries_user_updated_idx
  on public.earnline_entries (user_id, updated_at desc);

create index if not exists earnline_entries_client_idx
  on public.earnline_entries (client_id);

create index if not exists earnline_headings_user_updated_idx
  on public.earnline_headings (user_id, updated_at desc);

create index if not exists earnline_tombstones_user_deleted_idx
  on public.earnline_tombstones (user_id, deleted_at desc);

alter table public.earnline_clients enable row level security;
alter table public.earnline_entries enable row level security;
alter table public.earnline_headings enable row level security;
alter table public.earnline_tombstones enable row level security;

grant usage on schema public to authenticated;
grant select, insert, update, delete on public.earnline_clients to authenticated;
grant select, insert, update, delete on public.earnline_entries to authenticated;
grant select, insert, update, delete on public.earnline_headings to authenticated;
grant select, insert, update, delete on public.earnline_tombstones to authenticated;

drop policy if exists "earnline_clients_select_own" on public.earnline_clients;
create policy "earnline_clients_select_own"
on public.earnline_clients for select
to authenticated
using ((select auth.uid()) is not null and (select auth.uid()) = user_id);

drop policy if exists "earnline_clients_insert_own" on public.earnline_clients;
create policy "earnline_clients_insert_own"
on public.earnline_clients for insert
to authenticated
with check ((select auth.uid()) is not null and (select auth.uid()) = user_id);

drop policy if exists "earnline_clients_update_own" on public.earnline_clients;
create policy "earnline_clients_update_own"
on public.earnline_clients for update
to authenticated
using ((select auth.uid()) is not null and (select auth.uid()) = user_id)
with check ((select auth.uid()) is not null and (select auth.uid()) = user_id);

drop policy if exists "earnline_clients_delete_own" on public.earnline_clients;
create policy "earnline_clients_delete_own"
on public.earnline_clients for delete
to authenticated
using ((select auth.uid()) is not null and (select auth.uid()) = user_id);

drop policy if exists "earnline_entries_select_own" on public.earnline_entries;
create policy "earnline_entries_select_own"
on public.earnline_entries for select
to authenticated
using ((select auth.uid()) is not null and (select auth.uid()) = user_id);

drop policy if exists "earnline_entries_insert_own" on public.earnline_entries;
create policy "earnline_entries_insert_own"
on public.earnline_entries for insert
to authenticated
with check ((select auth.uid()) is not null and (select auth.uid()) = user_id);

drop policy if exists "earnline_entries_update_own" on public.earnline_entries;
create policy "earnline_entries_update_own"
on public.earnline_entries for update
to authenticated
using ((select auth.uid()) is not null and (select auth.uid()) = user_id)
with check ((select auth.uid()) is not null and (select auth.uid()) = user_id);

drop policy if exists "earnline_entries_delete_own" on public.earnline_entries;
create policy "earnline_entries_delete_own"
on public.earnline_entries for delete
to authenticated
using ((select auth.uid()) is not null and (select auth.uid()) = user_id);

drop policy if exists "earnline_headings_select_own" on public.earnline_headings;
create policy "earnline_headings_select_own"
on public.earnline_headings for select
to authenticated
using ((select auth.uid()) is not null and (select auth.uid()) = user_id);

drop policy if exists "earnline_headings_insert_own" on public.earnline_headings;
create policy "earnline_headings_insert_own"
on public.earnline_headings for insert
to authenticated
with check ((select auth.uid()) is not null and (select auth.uid()) = user_id);

drop policy if exists "earnline_headings_update_own" on public.earnline_headings;
create policy "earnline_headings_update_own"
on public.earnline_headings for update
to authenticated
using ((select auth.uid()) is not null and (select auth.uid()) = user_id)
with check ((select auth.uid()) is not null and (select auth.uid()) = user_id);

drop policy if exists "earnline_headings_delete_own" on public.earnline_headings;
create policy "earnline_headings_delete_own"
on public.earnline_headings for delete
to authenticated
using ((select auth.uid()) is not null and (select auth.uid()) = user_id);

drop policy if exists "earnline_tombstones_select_own" on public.earnline_tombstones;
create policy "earnline_tombstones_select_own"
on public.earnline_tombstones for select
to authenticated
using ((select auth.uid()) is not null and (select auth.uid()) = user_id);

drop policy if exists "earnline_tombstones_insert_own" on public.earnline_tombstones;
create policy "earnline_tombstones_insert_own"
on public.earnline_tombstones for insert
to authenticated
with check ((select auth.uid()) is not null and (select auth.uid()) = user_id);

drop policy if exists "earnline_tombstones_update_own" on public.earnline_tombstones;
create policy "earnline_tombstones_update_own"
on public.earnline_tombstones for update
to authenticated
using ((select auth.uid()) is not null and (select auth.uid()) = user_id)
with check ((select auth.uid()) is not null and (select auth.uid()) = user_id);

drop policy if exists "earnline_tombstones_delete_own" on public.earnline_tombstones;
create policy "earnline_tombstones_delete_own"
on public.earnline_tombstones for delete
to authenticated
using ((select auth.uid()) is not null and (select auth.uid()) = user_id);
