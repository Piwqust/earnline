update public.earnline_entries
set status = 'paid'
where status = 'logged';

alter table public.earnline_entries
  drop constraint if exists earnline_entries_status_check;

alter table public.earnline_entries
  add constraint earnline_entries_status_check
  check (status in ('paid', 'inProgress', 'canceled'));
