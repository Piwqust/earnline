-- Existing databases applied 20260729100000 before its explicit role revoke.
-- Trigger functions are implementation details and must not be RPC-callable.
revoke all on function public.earnline_stamp_tombstone()
  from anon, authenticated, public;
