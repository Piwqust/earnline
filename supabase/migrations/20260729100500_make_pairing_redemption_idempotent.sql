-- A client retry after a lost successful response must recover the original
-- device session, not burn the one-use token or create a second identity.

alter table public.earnline_pairing_tokens
  add column if not exists redeem_request_id uuid;

alter table public.earnline_pairing_tokens
  drop constraint if exists earnline_pairing_tokens_redemption_shape_check,
  add constraint earnline_pairing_tokens_redemption_shape_check check (
    (redeemed_at is null and redeemed_by is null and redeem_request_id is null)
    or (redeemed_at is not null and redeemed_by is not null)
  );

drop function if exists public.earnline_redeem_pairing_token_for_user(uuid, uuid);

create or replace function public.earnline_redeem_pairing_token_for_user(
  p_token uuid,
  p_user_id uuid,
  p_request_id uuid
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
  if p_request_id is null then
    raise exception 'A pairing request identifier is required.';
  end if;

  select coalesce((raw_app_meta_data ->> 'earnline_device')::boolean, false)
  into device_claim
  from auth.users
  where id = p_user_id;
  if not coalesce(device_claim, false) then
    raise exception 'A server-issued device identity is required.';
  end if;

  select * into pairing
  from public.earnline_pairing_tokens
  where token = p_token
  for update;
  if not found then
    raise exception 'This pairing code is invalid.';
  end if;

  if pairing.redeemed_at is not null then
    if pairing.redeem_request_id = p_request_id and pairing.redeemed_by = p_user_id then
      return pairing.workspace_id;
    end if;
    raise exception 'This pairing code has already been used.';
  end if;
  if pairing.expires_at <= statement_timestamp() then
    raise exception 'This pairing code has expired.';
  end if;
  if exists (
    select 1 from public.earnline_workspace_members member where member.user_id = p_user_id
  ) then
    raise exception 'This device is already paired.';
  end if;

  insert into public.earnline_workspace_members (workspace_id, user_id, role)
  values (pairing.workspace_id, p_user_id, 'device');

  update public.earnline_pairing_tokens
  set redeemed_by = p_user_id,
      redeemed_at = statement_timestamp(),
      redeem_request_id = p_request_id
  where token = pairing.token;

  return pairing.workspace_id;
end;
$$;

revoke all on function public.earnline_redeem_pairing_token_for_user(uuid, uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.earnline_redeem_pairing_token_for_user(uuid, uuid, uuid)
  to service_role;
