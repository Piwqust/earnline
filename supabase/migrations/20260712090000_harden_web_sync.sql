-- Keep the checked-in snapshot and incremental migrations equivalent.
-- Row clocks and tombstone clocks are server authoritative. Tombstones are
-- retained and replayed in full by clients; no age-based pruning is safe for a
-- device that can remain offline indefinitely.

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

do $$
declare
  table_name text;
begin
  foreach table_name in array array['earnline_clients', 'earnline_entries', 'earnline_headings', 'earnline_profiles']
  loop
    execute format('drop trigger if exists earnline_set_updated_at on public.%I', table_name);
    execute format(
      'create trigger earnline_set_updated_at before insert or update on public.%I '
      || 'for each row execute function public.earnline_set_updated_at()', table_name
    );
  end loop;
end $$;

create or replace function public.earnline_set_tombstone_clock()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.deleted_at := now();
  if tg_op = 'INSERT' then
    new.created_at := now();
  else
    new.created_at := old.created_at;
  end if;
  return new;
end;
$$;

drop trigger if exists earnline_set_tombstone_clock on public.earnline_tombstones;
create trigger earnline_set_tombstone_clock
before insert or update on public.earnline_tombstones
for each row execute function public.earnline_set_tombstone_clock();

do $$
declare
  table_name text;
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
  foreach table_name in array array[
    'earnline_clients', 'earnline_entries', 'earnline_headings', 'earnline_tombstones', 'earnline_profiles'
  ]
  loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = table_name
    ) then
      execute format('alter publication supabase_realtime add table public.%I', table_name);
    end if;
  end loop;
end $$;
