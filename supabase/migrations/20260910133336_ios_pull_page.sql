-- A bounded read-only transport. The caller's RLS still applies to every row.
-- Existing table clients remain supported and no ledger records are changed.
create or replace function public.earnline_pull_page(
  p_workspace_id text,
  p_since jsonb default '{}'::jsonb,
  p_before jsonb default '{}'::jsonb,
  p_done text[] default '{}'::text[]
) returns jsonb
language plpgsql stable security invoker set search_path = '' as $$
declare
  table_name text;
  result jsonb := '{}'::jsonb;
  rows jsonb;
  lower_stamp timestamptz;
  upper_stamp timestamptz;
  upper_id uuid;
begin
  if auth.uid() is null or not public.earnline_has_workspace_access(p_workspace_id) then
    raise insufficient_privilege using message = 'Workspace access required.';
  end if;
  if jsonb_typeof(p_since) is distinct from 'object'
     or jsonb_typeof(p_before) is distinct from 'object' or p_done is null then
    raise invalid_parameter_value using message = 'Invalid sync cursor.';
  end if;
  foreach table_name in array array['earnline_clients','earnline_headings',
    'earnline_entries','earnline_project_icons','earnline_month_reviews'] loop
    if table_name = any(p_done) then
      rows := '[]'::jsonb;
    else
      lower_stamp := (p_since->>table_name)::timestamptz;
      upper_stamp := (p_before->table_name->>'timestamp')::timestamptz;
      upper_id := (p_before->table_name->>'id')::uuid;
      if (upper_stamp is null) <> (upper_id is null) then
        raise invalid_parameter_value using message = 'Incomplete sync cursor.';
      end if;
      execute format('select coalesce(jsonb_agg(to_jsonb(page)), ''[]''::jsonb) from (
        select * from public.%I where workspace_id = $1
          and ($2 is null or updated_at >= $2)
          and ($3 is null or (updated_at,id) < ($3,$4))
        order by updated_at desc, id desc limit 250) page', table_name)
        into rows using p_workspace_id, lower_stamp, upper_stamp, upper_id;
    end if;
    result := result || jsonb_build_object(table_name, rows);
  end loop;
  return result;
end;
$$;
revoke all on function public.earnline_pull_page(text,jsonb,jsonb,text[])
  from public, anon, authenticated, service_role;
grant execute on function public.earnline_pull_page(text,jsonb,jsonb,text[]) to authenticated;
notify pgrst, 'reload schema';
