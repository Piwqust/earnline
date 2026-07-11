-- One shared settings profile per personal workspace. The currency pair and
-- its rate are one atomic value: syncing only the number would make it
-- ambiguous on devices whose selected currencies differ.

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

alter table public.earnline_profiles enable row level security;

revoke all privileges on table public.earnline_profiles from public, anon, authenticated;
grant select, insert, update on table public.earnline_profiles to anon, authenticated;

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
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'earnline_profiles'
  ) then
    alter publication supabase_realtime add table public.earnline_profiles;
  end if;
end $$;
