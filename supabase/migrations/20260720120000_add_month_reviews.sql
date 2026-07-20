-- Month reviews belong to the authenticated workspace model introduced in
-- 20260714123553_authenticated_workspaces_cutover.sql. They deliberately have
-- no delete permission: reopening a month updates the same shared row.

create table if not exists public.earnline_month_reviews (
  id uuid primary key,
  workspace_id text not null,
  month_start date not null
    constraint earnline_month_reviews_month_start_check check (extract(day from month_start) = 1),
  note text not null default ''
    constraint earnline_month_reviews_note_length_check check (char_length(note) <= 280),
  closed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint earnline_month_reviews_workspace_month_unique unique (workspace_id, month_start)
);

create index if not exists earnline_month_reviews_workspace_updated_idx
  on public.earnline_month_reviews (workspace_id, updated_at desc);

alter table public.earnline_month_reviews enable row level security;

-- The Data API needs explicit table privileges. RLS below remains the
-- authorization boundary and checks the caller's workspace membership.
revoke all on table public.earnline_month_reviews from public, anon, authenticated;
grant usage on schema public to authenticated;
grant select, insert, update on table public.earnline_month_reviews to authenticated;
grant execute on function public.earnline_has_workspace_access(text) to authenticated;

drop policy if exists "earnline_month_reviews_select_workspace"
  on public.earnline_month_reviews;
drop policy if exists "earnline_month_reviews_insert_workspace"
  on public.earnline_month_reviews;
drop policy if exists "earnline_month_reviews_update_workspace"
  on public.earnline_month_reviews;
drop policy if exists "earnline_month_reviews_select_member"
  on public.earnline_month_reviews;
drop policy if exists "earnline_month_reviews_insert_member"
  on public.earnline_month_reviews;
drop policy if exists "earnline_month_reviews_update_member"
  on public.earnline_month_reviews;

create policy "earnline_month_reviews_select_member"
on public.earnline_month_reviews for select to authenticated
using ((select public.earnline_has_workspace_access(workspace_id)));

create policy "earnline_month_reviews_insert_member"
on public.earnline_month_reviews for insert to authenticated
with check ((select public.earnline_has_workspace_access(workspace_id)));

create policy "earnline_month_reviews_update_member"
on public.earnline_month_reviews for update to authenticated
using ((select public.earnline_has_workspace_access(workspace_id)))
with check ((select public.earnline_has_workspace_access(workspace_id)));

drop trigger if exists earnline_set_updated_at on public.earnline_month_reviews;
create trigger earnline_set_updated_at
before insert or update on public.earnline_month_reviews
for each row execute function public.earnline_set_updated_at();

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'earnline_month_reviews'
  ) then
    alter publication supabase_realtime add table public.earnline_month_reviews;
  end if;
end $$;
