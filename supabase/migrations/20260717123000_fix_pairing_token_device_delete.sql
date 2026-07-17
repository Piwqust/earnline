-- Redeemed pairing tokens are short-lived audit artifacts owned by the
-- server-issued device identity. Deleting or revoking that identity must also
-- remove its token; SET NULL would violate the paired redeemed_by/redeemed_at
-- invariant and make device revocation fail.

alter table public.earnline_pairing_tokens
  drop constraint if exists earnline_pairing_tokens_redeemed_by_fkey;

alter table public.earnline_pairing_tokens
  add constraint earnline_pairing_tokens_redeemed_by_fkey
  foreign key (redeemed_by) references auth.users(id) on delete cascade;
