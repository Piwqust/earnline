-- A4RD-15, phase 1: introduce account ownership without changing the
-- established legacy-workspace policies yet. The operator handoff happens
-- after this migration and before the cutover migration.

create table if not exists public.earnline_workspaces (
  id text primary key,
  owner_id uuid unique references auth.users(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table if not exists public.earnline_workspace_members (
  workspace_id text not null references public.earnline_workspaces(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner', 'device')),
  created_at timestamptz not null default now(),
  primary key (workspace_id, user_id),
  unique (user_id)
);

create table if not exists public.earnline_pairing_tokens (
  token uuid primary key default gen_random_uuid(),
  workspace_id text not null references public.earnline_workspaces(id) on delete cascade,
  expires_at timestamptz not null,
  redeemed_by uuid references auth.users(id) on delete cascade,
  redeemed_at timestamptz,
  created_at timestamptz not null default now(),
  check ((redeemed_by is null) = (redeemed_at is null))
);

create index if not exists earnline_pairing_tokens_expiry_idx
  on public.earnline_pairing_tokens (expires_at)
  where redeemed_at is null;

-- Discover the current private workspace from data already present in the
-- project. The value is intentionally never written into this repository.
insert into public.earnline_workspaces (id)
select distinct workspace_id
from (
  select workspace_id from public.earnline_clients
  union
  select workspace_id from public.earnline_entries
  union
  select workspace_id from public.earnline_headings
  union
  select workspace_id from public.earnline_tombstones
  union
  select workspace_id from public.earnline_profiles
  union
  select workspace_id from public.earnline_project_icons
) legacy
where workspace_id is not null and btrim(workspace_id) <> ''
on conflict (id) do nothing;

alter table public.earnline_workspaces enable row level security;
alter table public.earnline_workspace_members enable row level security;
alter table public.earnline_pairing_tokens enable row level security;

-- Membership lookup is deliberately a narrowly-scoped security-definer
-- helper. It avoids recursive RLS evaluation while still deriving the caller
-- from auth.uid(), never from client input.
create or replace function public.earnline_has_workspace_access(target_workspace_id text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.earnline_workspace_members member
    where member.workspace_id = target_workspace_id
      and member.user_id = (select auth.uid())
  );
$$;

create or replace function public.earnline_current_workspace()
returns table (workspace_id text, membership_role text)
language sql
stable
security definer
set search_path = ''
as $$
  select member.workspace_id, member.role
  from public.earnline_workspace_members member
  where member.user_id = (select auth.uid())
  order by case member.role when 'owner' then 0 else 1 end, member.created_at
  limit 1;
$$;

-- This is intentionally not called automatically by either client. Existing
-- installs must first be hand-bound to their legacy workspace by the operator.
-- It remains available for a genuinely new permanent account.
create or replace function public.earnline_create_workspace()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  new_workspace_id text;
  caller_id uuid := auth.uid();
begin
  if caller_id is null then
    raise exception 'An authenticated account is required.';
  end if;
  if coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then
    raise exception 'Paired devices cannot create a workspace.';
  end if;
  if exists (
    select 1 from public.earnline_workspace_members member where member.user_id = caller_id
  ) then
    raise exception 'This account already has a workspace.';
  end if;

  new_workspace_id := gen_random_uuid()::text;
  insert into public.earnline_workspaces (id, owner_id) values (new_workspace_id, caller_id);
  insert into public.earnline_workspace_members (workspace_id, user_id, role)
  values (new_workspace_id, caller_id, 'owner');
  return new_workspace_id;
end;
$$;

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

create or replace function public.earnline_redeem_pairing_token(p_token uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  pairing public.earnline_pairing_tokens%rowtype;
begin
  if caller_id is null then
    raise exception 'A paired device identity is required.';
  end if;
  if not coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then
    raise exception 'Only a paired device identity can redeem this code.';
  end if;
  if exists (select 1 from public.earnline_workspace_members member where member.user_id = caller_id) then
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
  values (pairing.workspace_id, caller_id, 'device');
  update public.earnline_pairing_tokens
  set redeemed_by = caller_id, redeemed_at = now()
  where token = pairing.token;

  return pairing.workspace_id;
end;
$$;

-- Supabase grants EXECUTE to API roles by default for new functions. Revoke
-- each role explicitly before adding back only the RPCs the authenticated
-- clients need; `PUBLIC` alone does not remove role-specific default grants.
revoke all on function public.earnline_has_workspace_access(text) from public, anon, authenticated, service_role;
revoke all on function public.earnline_current_workspace() from public, anon, authenticated, service_role;
revoke all on function public.earnline_create_workspace() from public, anon, authenticated, service_role;
revoke all on function public.earnline_create_pairing_token() from public, anon, authenticated, service_role;
revoke all on function public.earnline_redeem_pairing_token(uuid) from public, anon, authenticated, service_role;
grant execute on function public.earnline_current_workspace() to authenticated;
grant execute on function public.earnline_create_workspace() to authenticated;
grant execute on function public.earnline_create_pairing_token() to authenticated;
grant execute on function public.earnline_redeem_pairing_token(uuid) to authenticated;
