-- Enforce the same wire contract in Postgres, Edge, and the native clients.
-- The preflight deliberately aborts rather than rewriting historical income:
-- an operator must inspect any legacy row that does not meet the published
-- contract before this migration is applied to a live project.

do $$
begin
  if exists (
    select 1 from public.earnline_clients
    where char_length(name) not between 1 and 24
       or name <> btrim(name)
       or color_hex !~ '^#[0-9A-Fa-f]{6}$'
  ) then
    raise exception 'earnline_clients contains rows outside the sync contract';
  end if;
  if exists (
    select 1 from public.earnline_entries
    where amount <= 0 or amount > 1000000000
       or currency_code not in ('USD', 'EUR', 'GBP', 'RUB', 'UAH')
       or (project is not null and (char_length(project) > 40 or project <> btrim(project)))
       or char_length(task) not between 1 and 140
       or task <> btrim(task)
  ) then
    raise exception 'earnline_entries contains rows outside the sync contract';
  end if;
  if exists (
    select 1 from public.earnline_headings
    where char_length(title) not between 1 and 40 or title <> btrim(title)
  ) then
    raise exception 'earnline_headings contains rows outside the sync contract';
  end if;
end;
$$;

alter table public.earnline_clients
  drop constraint if exists earnline_clients_name_contract_check,
  drop constraint if exists earnline_clients_color_hex_contract_check,
  add constraint earnline_clients_name_contract_check
    check (char_length(name) between 1 and 24 and name = btrim(name)),
  add constraint earnline_clients_color_hex_contract_check
    check (color_hex ~ '^#[0-9A-Fa-f]{6}$');

alter table public.earnline_entries
  drop constraint if exists earnline_entries_amount_contract_check,
  drop constraint if exists earnline_entries_currency_code_contract_check,
  drop constraint if exists earnline_entries_project_contract_check,
  drop constraint if exists earnline_entries_task_contract_check,
  add constraint earnline_entries_amount_contract_check
    check (amount > 0 and amount <= 1000000000),
  add constraint earnline_entries_currency_code_contract_check
    check (currency_code in ('USD', 'EUR', 'GBP', 'RUB', 'UAH')),
  add constraint earnline_entries_project_contract_check
    check (project is null or (char_length(project) <= 40 and project = btrim(project))),
  add constraint earnline_entries_task_contract_check
    check (char_length(task) between 1 and 140 and task = btrim(task));

alter table public.earnline_headings
  drop constraint if exists earnline_headings_title_contract_check,
  add constraint earnline_headings_title_contract_check
    check (char_length(title) between 1 and 40 and title = btrim(title));

-- Project symbols are defined in supabase/contract/project-symbols.json and
-- checked against this constraint in scripts/verify-project-symbol-contract.mjs.
alter table public.earnline_project_icons
  drop constraint if exists earnline_project_icons_symbol_name_check,
  add constraint earnline_project_icons_symbol_name_check check (symbol_name in (
    'folder', 'briefcase', 'display', 'paintpalette', 'camera', 'video',
    'music.note', 'doc.text', 'megaphone', 'cart', 'globe',
    'wrench.and.screwdriver', 'shippingbox', 'sparkles',
    'chart.line.uptrend.xyaxis', 'building.2', 'app', 'cloud', 'terminal',
    'bolt', 'cpu', 'photo', 'pencil', 'theater', 'creditcard', 'banknote',
    'person.2', 'calendar', 'storefront', 'bag', 'book.closed',
    'graduationcap', 'lightbulb', 'target', 'paintbrush', 'wand.and.stars',
    'mic', 'headphones', 'keyboard', 'server.rack', 'network', 'gearshape',
    'tag', 'receipt', 'phone', 'envelope', 'person.2.wave.2',
    'mappin.and.ellipse'
  ));

-- A legacy client could write a tombstone far into the future and then keep a
-- restored row deleted indefinitely. Clamp only impossible future values; do
-- not rewrite valid deletion history or otherwise change customer data.
update public.earnline_tombstones
set deleted_at = statement_timestamp()
where deleted_at > statement_timestamp();

-- The deletion timestamp is an ordering authority. Override any client clock
-- on insert and prohibit subsequent mutation, while allowing idempotent
-- INSERT .. ON CONFLICT DO NOTHING retries.
create or replace function public.earnline_stamp_tombstone()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op <> 'INSERT' then
    raise exception 'Tombstones are append-only.';
  end if;
  new.deleted_at := statement_timestamp();
  new.created_at := statement_timestamp();
  return new;
end;
$$;

drop trigger if exists earnline_set_tombstone_clock on public.earnline_tombstones;
drop trigger if exists earnline_stamp_tombstone on public.earnline_tombstones;
create trigger earnline_stamp_tombstone
before insert or update on public.earnline_tombstones
for each row execute function public.earnline_stamp_tombstone();

revoke update, delete on table public.earnline_tombstones from authenticated;
drop policy if exists earnline_tombstones_update_member on public.earnline_tombstones;
drop policy if exists earnline_tombstones_delete_member on public.earnline_tombstones;
-- PostgreSQL's default EXECUTE grant is assigned separately to `anon` and
-- `authenticated` on this project, so revoking only from `public` would leave
-- a newly-created trigger function callable through PostgREST.
revoke all on function public.earnline_stamp_tombstone()
  from anon, authenticated, public;
do $$
begin
  -- Production predates the legacy helper, while staging still has it from an
  -- earlier hardening migration. Revoke it only when it exists so this
  -- invariant migration remains safe for both histories.
  if to_regprocedure('public.earnline_set_tombstone_clock()') is not null then
    revoke all on function public.earnline_set_tombstone_clock()
      from anon, authenticated, public;
  end if;
end;
$$;

-- Force PostgREST to see the newly added month-review table and constraints
-- immediately after a deployment instead of waiting for its schema cache.
notify pgrst, 'reload schema';
