-- Replace unrestricted anonymous Auth sign-up with server-issued device
-- identities, add owner-visible device lifecycle RPCs, and clean abandoned
-- pairing artifacts. Apply after the authenticated workspace cutover.

grant execute on function public.earnline_has_workspace_access(text) to authenticated;

-- Older builds used a public anonymous Auth session followed by this RPC.
-- New builds redeem through the service-only function below, so no client can
-- create an unpaired identity or attach an arbitrary authenticated account.
revoke all on function public.earnline_redeem_pairing_token(uuid)
  from public, anon, authenticated, service_role;

create or replace function public.earnline_redeem_pairing_token_for_user(
  p_token uuid,
  p_user_id uuid
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  pairing public.earnline_pairing_tokens%rowtype;
  device_claim boolean;
begin
  select coalesce((raw_app_meta_data ->> 'earnline_device')::boolean, false)
  into device_claim
  from auth.users
  where id = p_user_id;

  if not coalesce(device_claim, false) then
    raise exception 'A server-issued device identity is required.';
  end if;
  if exists (
    select 1 from public.earnline_workspace_members member where member.user_id = p_user_id
  ) then
    raise exception 'This device is already paired.';
  end if;

  select * into pairing
  from public.earnline_pairing_tokens
  where token = p_token
  for update;

  if not found then
    raise exception 'This pairing code is invalid.';
  end if;
  if pairing.redeemed_at is not null then
    raise exception 'This pairing code has already been used.';
  end if;
  if pairing.expires_at <= now() then
    raise exception 'This pairing code has expired.';
  end if;

  insert into public.earnline_workspace_members (workspace_id, user_id, role)
  values (pairing.workspace_id, p_user_id, 'device');

  update public.earnline_pairing_tokens
  set redeemed_by = p_user_id, redeemed_at = now()
  where token = pairing.token;

  return pairing.workspace_id;
end;
$$;

revoke all on function public.earnline_redeem_pairing_token_for_user(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.earnline_redeem_pairing_token_for_user(uuid, uuid)
  to service_role;

create or replace function public.earnline_list_devices()
returns table (
  user_id uuid,
  created_at timestamptz,
  last_sign_in_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  caller_workspace_id text;
begin
  select member.workspace_id into caller_workspace_id
  from public.earnline_workspace_members member
  where member.user_id = caller_id and member.role = 'owner';

  if caller_workspace_id is null then
    raise exception 'Only the workspace owner can manage devices.';
  end if;

  return query
  select member.user_id, member.created_at, identity.last_sign_in_at
  from public.earnline_workspace_members member
  join auth.users identity on identity.id = member.user_id
  where member.workspace_id = caller_workspace_id and member.role = 'device'
  order by coalesce(identity.last_sign_in_at, member.created_at) desc;
end;
$$;

create or replace function public.earnline_revoke_device(p_user_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  caller_workspace_id text;
  removed_count integer;
begin
  select member.workspace_id into caller_workspace_id
  from public.earnline_workspace_members member
  where member.user_id = caller_id and member.role = 'owner';

  if caller_workspace_id is null then
    raise exception 'Only the workspace owner can manage devices.';
  end if;

  delete from auth.users identity
  using public.earnline_workspace_members member
  where identity.id = p_user_id
    and member.user_id = identity.id
    and member.workspace_id = caller_workspace_id
    and member.role = 'device';
  get diagnostics removed_count = row_count;
  return removed_count = 1;
end;
$$;

revoke all on function public.earnline_list_devices()
  from public, anon, authenticated, service_role;
revoke all on function public.earnline_revoke_device(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.earnline_list_devices() to authenticated;
grant execute on function public.earnline_revoke_device(uuid) to authenticated;

-- Signing out a paired device must remove the server-side identity as well as
-- its local refresh token. This keeps the owner device list accurate and
-- ensures the same device needs a fresh one-time code before it can sync.
create or replace function public.earnline_disconnect_current_device()
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  removed_count integer;
begin
  if caller_id is null or not exists (
    select 1
    from auth.users identity
    where identity.id = caller_id
      and coalesce((identity.raw_app_meta_data ->> 'earnline_device')::boolean, false)
  ) then
    raise exception 'Only a paired device can disconnect itself.';
  end if;

  delete from auth.users identity where identity.id = caller_id;
  get diagnostics removed_count = row_count;
  return removed_count = 1;
end;
$$;

revoke all on function public.earnline_disconnect_current_device()
  from public, anon, authenticated, service_role;
grant execute on function public.earnline_disconnect_current_device() to authenticated;

-- These columns belonged to the original per-Auth-user schema. Workspace
-- membership is now the sole ownership boundary, so retaining nullable copies
-- would invite clients and operators to use the wrong authorization model.
drop index if exists public.earnline_clients_user_updated_idx;
drop index if exists public.earnline_entries_user_updated_idx;
drop index if exists public.earnline_headings_user_updated_idx;
drop index if exists public.earnline_tombstones_user_deleted_idx;
alter table public.earnline_clients drop column if exists user_id;
alter table public.earnline_entries drop column if exists user_id;
alter table public.earnline_headings drop column if exists user_id;
alter table public.earnline_tombstones drop column if exists user_id;

create or replace function public.earnline_cleanup_pairing_artifacts()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  removed_users integer := 0;
  removed_tokens integer := 0;
begin
  delete from auth.users identity
  where coalesce((identity.raw_app_meta_data ->> 'earnline_device')::boolean, false)
    and identity.created_at < now() - interval '1 hour'
    and not exists (
      select 1 from public.earnline_workspace_members member where member.user_id = identity.id
    );
  get diagnostics removed_users = row_count;

  delete from public.earnline_pairing_tokens token
  where token.expires_at < now() - interval '1 day';
  get diagnostics removed_tokens = row_count;

  return removed_users + removed_tokens;
end;
$$;

revoke all on function public.earnline_cleanup_pairing_artifacts()
  from public, anon, authenticated, service_role;
grant execute on function public.earnline_cleanup_pairing_artifacts() to service_role;

create extension if not exists pg_cron with schema pg_catalog;

do $$
declare
  existing_job bigint;
begin
  select jobid into existing_job
  from cron.job
  where jobname = 'earnline-cleanup-pairing-artifacts';
  if existing_job is not null then
    perform cron.unschedule(existing_job);
  end if;
  perform cron.schedule(
    'earnline-cleanup-pairing-artifacts',
    '17 3 * * *',
    'select public.earnline_cleanup_pairing_artifacts()'
  );
end;
$$;
