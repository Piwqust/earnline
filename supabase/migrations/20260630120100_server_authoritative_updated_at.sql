-- Make updated_at server-authoritative so the sync conflict policy
-- (last-write-wins) can't be skewed by client clocks. A BEFORE INSERT/UPDATE
-- trigger stamps now() on every write to the row tables. Tombstones order by
-- deleted_at (set on insert) and need no trigger.

create or replace function public.earnline_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

do $$
declare
  t text;
begin
  foreach t in array array['earnline_clients', 'earnline_entries', 'earnline_headings']
  loop
    execute format('drop trigger if exists earnline_set_updated_at on public.%I', t);
    execute format(
      'create trigger earnline_set_updated_at before insert or update on public.%I '
      || 'for each row execute function public.earnline_set_updated_at()', t
    );
  end loop;
end $$;
