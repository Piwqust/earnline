-- Qualify RETURNING fields so they cannot conflict with the table-function
-- output names (`pairing_token`, `expires_at`) in PL/pgSQL.

create or replace function public.earnline_create_pairing_token()
returns table (pairing_token uuid, expires_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  caller_workspace_id text;
begin
  if caller_id is null or coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then
    raise exception 'Only the workspace owner can pair a device.';
  end if;

  select member.workspace_id into caller_workspace_id
  from public.earnline_workspace_members member
  where member.user_id = caller_id and member.role = 'owner';

  if caller_workspace_id is null then
    raise exception 'Only the workspace owner can pair a device.';
  end if;

  return query
  insert into public.earnline_pairing_tokens (workspace_id, expires_at)
  values (caller_workspace_id, now() + interval '10 minutes')
  returning earnline_pairing_tokens.token, earnline_pairing_tokens.expires_at;
end;
$$;

revoke all on function public.earnline_create_pairing_token() from public, anon, authenticated, service_role;
grant execute on function public.earnline_create_pairing_token() to authenticated;
