-- Workspace-wide SF Symbol choices for the existing free-form Entry.project
-- field. Resetting a choice is an upsert to `folder`, so this additive table
-- deliberately has no delete policy or tombstone entity.

create table if not exists public.earnline_project_icons (
  id uuid primary key,
  workspace_id text not null,
  project_key text not null
    constraint earnline_project_icons_project_key_check check (
      char_length(project_key) between 1 and 40
      and project_key = lower(btrim(project_key))
      and project_key !~ '[[:space:]]{2,}'
    ),
  symbol_name text not null default 'folder'
    constraint earnline_project_icons_symbol_name_check check (symbol_name in (
      'folder', 'briefcase', 'display', 'paintpalette', 'camera', 'video',
      'music.note', 'doc.text', 'megaphone', 'cart', 'globe',
      'wrench.and.screwdriver', 'shippingbox', 'sparkles',
      'chart.line.uptrend.xyaxis', 'building.2'
    )),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint earnline_project_icons_workspace_key_unique unique (workspace_id, project_key)
);

create index if not exists earnline_project_icons_workspace_updated_idx
  on public.earnline_project_icons (workspace_id, updated_at desc);

alter table public.earnline_project_icons enable row level security;

revoke all privileges on table public.earnline_project_icons from public, anon, authenticated;
grant select, insert, update on table public.earnline_project_icons to anon, authenticated;

-- Keep the repository free of the private workspace identifier. This
-- On an established workspace, derive the already-authorized value from
-- existing rows before installing the same check/default/RLS contract on the
-- new table. A clean staging database has no value to derive; in that case
-- leave RLS enabled without policies (deny all) until the authenticated
-- workspace cutover installs membership policies a few migrations later.
do $$
declare
  allowed_workspace text;
begin
  select workspace_id into allowed_workspace
  from public.earnline_clients
  limit 1;

  if allowed_workspace is null then
    select workspace_id into allowed_workspace
    from public.earnline_profiles
    limit 1;
  end if;

  if allowed_workspace is null then
    return;
  end if;

  alter table public.earnline_project_icons
    drop constraint if exists earnline_project_icons_workspace_id_check;
  execute format(
    'alter table public.earnline_project_icons alter column workspace_id set default %L',
    allowed_workspace
  );
  execute format(
    'alter table public.earnline_project_icons add constraint '
    || 'earnline_project_icons_workspace_id_check check (workspace_id = %L)',
    allowed_workspace
  );

  drop policy if exists "earnline_project_icons_select_workspace"
    on public.earnline_project_icons;
  execute format(
    'create policy "earnline_project_icons_select_workspace" '
    || 'on public.earnline_project_icons for select to anon, authenticated '
    || 'using (workspace_id = %L)',
    allowed_workspace
  );

  drop policy if exists "earnline_project_icons_insert_workspace"
    on public.earnline_project_icons;
  execute format(
    'create policy "earnline_project_icons_insert_workspace" '
    || 'on public.earnline_project_icons for insert to anon, authenticated '
    || 'with check (workspace_id = %L)',
    allowed_workspace
  );

  drop policy if exists "earnline_project_icons_update_workspace"
    on public.earnline_project_icons;
  execute format(
    'create policy "earnline_project_icons_update_workspace" '
    || 'on public.earnline_project_icons for update to anon, authenticated '
    || 'using (workspace_id = %L) with check (workspace_id = %L)',
    allowed_workspace,
    allowed_workspace
  );
end $$;

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

drop trigger if exists earnline_set_updated_at on public.earnline_project_icons;
create trigger earnline_set_updated_at
before insert or update on public.earnline_project_icons
for each row execute function public.earnline_set_updated_at();

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'earnline_project_icons'
  ) then
    alter publication supabase_realtime add table public.earnline_project_icons;
  end if;
end $$;
