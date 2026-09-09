-- Opt-in, atomic compare-and-set for the native client. Existing clients keep
-- their table API; RLS and table constraints also apply inside this invoker RPC.
create or replace function public.earnline_set_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin
  if tg_op = 'UPDATE' then
    new.updated_at := greatest(clock_timestamp(), old.updated_at + interval '1 microsecond');
  else
    new.updated_at := clock_timestamp();
  end if;
  return new;
end;
$$;

create or replace function public.earnline_upsert_versioned(
  p_table text,
  p_workspace_id text,
  p_rows jsonb,
  p_expected_versions jsonb,
  p_force boolean default false
)
returns setof jsonb
language plpgsql security invoker set search_path = '' as $$
declare
  item jsonb;
  result jsonb;
  remote_stamp timestamptz;
  expected bigint;
  index integer := 0;
  key_column text;
  key_value text;
  assignments text;
  entity_name text;
begin
  if auth.uid() is null or not public.earnline_has_workspace_access(p_workspace_id) then
    raise insufficient_privilege using message = 'Workspace access required.';
  end if;
  if p_force is null or p_table is null or p_table not in ('earnline_clients', 'earnline_entries', 'earnline_headings',
                     'earnline_project_icons', 'earnline_month_reviews', 'earnline_profiles') then
    raise invalid_parameter_value using message = 'Unsupported sync table.';
  end if;
  if jsonb_typeof(p_rows) is distinct from 'array'
     or jsonb_typeof(p_expected_versions) is distinct from 'array'
     or jsonb_array_length(p_rows) not between 1 and 250
     or jsonb_array_length(p_rows) <> jsonb_array_length(p_expected_versions) then
    raise invalid_parameter_value using message = 'Invalid sync batch.';
  end if;
  key_column := case when p_table = 'earnline_profiles' then 'workspace_id' else 'id' end;
  entity_name := case p_table when 'earnline_clients' then 'client'
    when 'earnline_entries' then 'entry' when 'earnline_headings' then 'heading'
    when 'earnline_project_icons' then 'projectIcon' when 'earnline_month_reviews' then 'monthReview' end;
  select string_agg(format('%1$I = incoming.%1$I', a.attname), ', ' order by a.attnum)
    into assignments from pg_catalog.pg_attribute a
    where a.attrelid = format('public.%I', p_table)::regclass
      and a.attnum > 0 and not a.attisdropped
      and a.attname not in ('id', 'workspace_id', 'created_at', 'updated_at');

  for item in select value from jsonb_array_elements(p_rows) loop
    if jsonb_typeof(item) <> 'object' or item->>'workspace_id' is distinct from p_workspace_id then
      raise invalid_parameter_value using message = 'Batch workspace mismatch.';
    end if;
    expected := (p_expected_versions->>index)::bigint;
    index := index + 1;
    key_value := item->>key_column;
    remote_stamp := null;
    execute format('select updated_at from public.%I where %I::text = $1 and workspace_id = $2 for update',
                   p_table, key_column)
      into remote_stamp using key_value, p_workspace_id;
    if not p_force and (
      (remote_stamp is not null and (expected is null or
       round(extract(epoch from remote_stamp) * 1000000)::bigint <> expected))
      or (remote_stamp is null and expected is not null)
    ) then
      raise sqlstate 'PT409' using message = 'Cloud version changed.';
    end if;
    if remote_stamp is null then
      if not p_force and entity_name is not null and exists (
        select 1 from public.earnline_tombstones t where t.workspace_id = p_workspace_id
          and t.entity = entity_name and t.record_id::text = key_value
      ) then
        raise sqlstate 'PT409' using message = 'Cloud record was deleted.';
      end if;
      begin
        execute format('insert into public.%1$I select * from jsonb_populate_record(null::public.%1$I, $1) returning to_jsonb(%1$I.*)', p_table)
          into result using item;
      exception when unique_violation then
        -- Another writer can insert after our missing-row check. Never turn
        -- that race into an unconditional ON CONFLICT UPDATE.
        raise sqlstate 'PT409' using message = 'Cloud record was created concurrently.';
      end;
    else
      execute format('update public.%1$I as target set %2$s from jsonb_populate_record(null::public.%1$I, $1) incoming where target.%3$I::text = $2 and target.workspace_id = $3 returning to_jsonb(target.*)',
                     p_table, assignments, key_column)
        into result using item, key_value, p_workspace_id;
    end if;
    if result is null then
      raise sqlstate 'PT409' using message = 'Cloud record is no longer available.';
    end if;
    return next result;
  end loop;
end;
$$;
revoke all on function public.earnline_upsert_versioned(text, text, jsonb, jsonb, boolean)
  from public, anon, authenticated, service_role;
grant execute on function public.earnline_upsert_versioned(text, text, jsonb, jsonb, boolean) to authenticated;
notify pgrst, 'reload schema';
