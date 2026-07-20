-- Supabase grants EXECUTE to API roles by default for newly-created public
-- functions. The preparation migration is already live in production, so
-- explicitly remove those grants before the authentication rollout continues.

revoke all on function public.earnline_has_workspace_access(text) from public, anon, authenticated, service_role;
revoke all on function public.earnline_current_workspace() from public, anon, authenticated, service_role;
revoke all on function public.earnline_create_workspace() from public, anon, authenticated, service_role;
revoke all on function public.earnline_create_pairing_token() from public, anon, authenticated, service_role;
revoke all on function public.earnline_redeem_pairing_token(uuid) from public, anon, authenticated, service_role;

grant execute on function public.earnline_current_workspace() to authenticated;
grant execute on function public.earnline_create_workspace() to authenticated;
grant execute on function public.earnline_create_pairing_token() to authenticated;
grant execute on function public.earnline_redeem_pairing_token(uuid) to authenticated;
