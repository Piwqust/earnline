revoke all privileges on table public.earnline_clients from authenticated;
revoke all privileges on table public.earnline_entries from authenticated;
revoke all privileges on table public.earnline_headings from authenticated;
revoke all privileges on table public.earnline_tombstones from authenticated;

grant select, insert, update, delete on table public.earnline_clients to authenticated;
grant select, insert, update, delete on table public.earnline_entries to authenticated;
grant select, insert, update, delete on table public.earnline_headings to authenticated;
grant select, insert, update, delete on table public.earnline_tombstones to authenticated;
