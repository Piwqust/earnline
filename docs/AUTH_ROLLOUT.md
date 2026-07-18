# Private OAuth and device pairing rollout

This is an operator runbook for A4RD-15, not the product introduction. It
supports private sync and pairing for the iPhone-first app; begin with the
[project README](../README.md) or [documentation map](README.md) for the right
entry point. It deliberately separates compatible schema preparation from the
authorization cutover. Do not put a legacy workspace ID,
Supabase user ID, QR token, OAuth secret, service-role key, or a real web origin
in this repository, an issue, a screenshot, or shell history.

## 1. Configure Supabase Auth

In the Supabase Dashboard, enable only the Google, GitHub, and Apple providers.
Add the provider client secrets in the Dashboard or secret store, never in
either app. Allow these redirect URLs:

- `com.earnline.app://auth/callback`
- `com.earnline.app.dev://auth/callback` — only if OAuth should also work from
  the side-by-side `earnline-dev` testing build
- `https://YOUR_DEPLOYED_WEB_ORIGIN/auth/callback`
- the intentional local-development callback, if one is used

For Apple, iOS uses the native Sign in with Apple flow
(`signInWithIdToken`), so add the app bundle ID `com.earnline.app` to the
Apple provider's **Client IDs** field. No Services ID or generated secret key
is required until the web client also offers Apple; add those separately at
that point. The app target carries the `com.apple.developer.applesignin`
entitlement (generated from `ios-app/project.yml`), which release signing
requires to be present in the App ID configuration.

The iOS guest option ("Continue without an account") is entirely local to the
device: it creates no Supabase identity and needs no Dashboard configuration.
Keep Supabase anonymous sign-ins and new public sign-ups disabled. The
email/password provider can remain disabled: device sessions are minted from a
server-generated magic-link token without sending email. QR pairing uses the public
`earnline-pair-device` Edge Function, which validates a ten-minute one-use token
before creating a device-scoped identity. Invalid requests create no Auth user,
so the client does not need a CAPTCHA challenge.

Before continuing, create both the emergency REST export and a full database
backup as described in `docs/SUPABASE_OPERATIONS.md`.

## 2. Apply the compatible preparation migrations

Apply `20260714123552_authenticated_workspaces_prepare.sql`, followed
immediately by `20260714140000_harden_workspace_rpc_grants.sql`. Together they
create workspaces, members, ten-minute one-time pairing tokens, and the
owner-only RPCs while preserving the current legacy workspace policies. The
second migration is required because Supabase gives new public RPC functions
default API-role execute grants; it removes those grants before adding back
only the authenticated RPCs used by the apps.

Deploy the app builds after that migration. A permanent account with no
membership correctly sees **Workspace setup pending** instead of creating or
claiming a workspace in the client.

## 3. Sign in and privately hand off the legacy workspace

Sign in once with the intended Google or GitHub account. In a private operator
session, verify the exact user in the Auth dashboard, then run this parameterized
transaction with values supplied outside source control:

```sql
begin;

-- Verify the chosen user and provider in the dashboard before using its UUID.
update public.earnline_workspaces
set owner_id = '<VERIFIED_AUTH_USER_UUID>'
where id = '<LEGACY_WORKSPACE_ID>'
  and owner_id is null;

insert into public.earnline_workspace_members (workspace_id, user_id, role)
values ('<LEGACY_WORKSPACE_ID>', '<VERIFIED_AUTH_USER_UUID>', 'owner')
on conflict (user_id) do update
set workspace_id = excluded.workspace_id, role = 'owner';

commit;
```

Confirm that exactly one owner membership exists for the legacy workspace. Do
not expose the substituted SQL or its output. The first authenticated sync is
the point at which the account-scoped local store becomes active; the legacy
cache remains on disk until that successful sync rather than being deleted.

## 4. Cut over RLS, device lifecycle, and the web gateway

Apply `20260714123553_authenticated_workspaces_cutover.sql` only after the
handoff succeeds. It drops fixed-workspace checks, revokes `anon` access, and
grants each ledger table, profile, tombstone, and project-icon row only to a
workspace member. The pairing redemption RPC locks the token row, checks expiry,
and marks it used in the same transaction.

Immediately apply `20260717120000_secure_device_lifecycle.sql`. It adds the
owner-only device list/revoke RPCs, a service-only pairing redemption function,
self-disconnect for paired devices, and scheduled cleanup. It also removes the
obsolete per-user ownership columns and retires the older anonymous-client
redemption RPC. Then apply
`20260717123000_fix_pairing_token_device_delete.sql`, which makes device
revocation cascade its already-used one-time token instead of violating the
pairing-token integrity constraint.

Deploy `earnline-sync` after the cutover. Set only these function secrets:

```bash
supabase secrets set \
  EARNLINE_SCOPE_SALT="$(openssl rand -hex 32)" \
  EARNLINE_ALLOWED_ORIGINS="https://YOUR_DEPLOYED_WEB_ORIGIN"
supabase functions deploy earnline-sync
supabase functions deploy earnline-pair-device --no-verify-jwt
```

The sync function requires a Supabase bearer token, validates it server-side,
resolves the caller's membership, and performs every ledger operation with the
caller-scoped RLS client. It returns a salted opaque local scope and accepts no
workspace ID from the client. The pairing function accepts no existing session;
the one-use token is its only authorization and no service credential leaves
the function.

## 5. Verify and retire the legacy path

1. Verify Google and GitHub sign-in on iOS and the deployed web origin, and
   native Apple sign-in on an iOS device. Verify the guest option opens an
   empty local ledger with sync reporting Offline.
2. Generate a QR code from an owner device; redeem it once on a clean device;
   verify expiry and second redemption fail. Revoke it from Settings and verify
   that its refresh token can no longer restore access.
3. Confirm the publishable key alone receives no ledger rows and the web gateway
   returns no data without a valid user JWT. Run
   `scripts/verify-supabase-security.mjs`.
4. Confirm Test remains local-only, then remove all legacy capability secrets
   and fixed-workspace configuration from the deployment environment.

After the cutover is verified, rotate the publishable key in the Dashboard,
update only the private iOS build configuration and web deployment environment,
rebuild both clients, and rerun the verifier. Never rotate the service-role key
unless it was exposed; it exists only in Supabase-managed function secrets.

Run the iOS suite and `npm test`, `npm run typecheck`, and `npm run build` as
part of the release check. Provider configuration and the private handoff are
external operations, so they cannot be verified from a source checkout alone.
