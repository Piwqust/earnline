# earn›line — web app

Desktop-first React client for the same private Earnline ledger as the native
iOS app. IndexedDB is the local source of truth; Google/GitHub OAuth establishes
the browser session and a Supabase JWT authorizes production sync.

## Local development

```bash
cd web
npm ci
npm run dev
npm test
npm run typecheck
npm run build
```

Set the three browser-safe `VITE_…` values from [`.env.example`](.env.example).
The browser receives a publishable key, never a service-role key, a workspace ID,
or a capability. The app does not begin sync until a session resolves a private
workspace membership. The Edge Function returns a salted opaque IndexedDB scope,
so a different account does not reuse the prior account's local database.

## Deploy production sync

Follow the staged instructions in [`../docs/AUTH_ROLLOUT.md`](../docs/AUTH_ROLLOUT.md).
The function validates the bearer token, resolves the caller's workspace member
row, performs ledger operations with the caller-scoped RLS client, overwrites
every incoming `workspace_id`, batches concurrent reads, and keeps responses
free of the real workspace identifier.

## Sync guarantees

- Pull-before-push conflict detection prevents a reconnecting browser from
  silently overwriting newer iPhone changes.
- A conflict stops before either version is changed; Settings offers explicit
  cloud or browser resolution.
- Tombstones are server-timestamped, retained, and replayed in full. A device
  that was offline for months cannot miss a deletion because of a cursor or
  retention window.
- Each resolved account/workspace has a separate opaque IndexedDB database and cursor.
- Web Locks plus an atomic IndexedDB lease prevent simultaneous tab sync passes;
  BroadcastChannel propagates completion state.
- Proxy mode batches concurrent row reads, polls every two minutes while visible,
  and also syncs immediately on local changes, focus, and reconnect. Development
  direct mode additionally reports Supabase Realtime channel state. Polling is
  required for correctness because Realtime DELETE filters are not sufficient.
- Browser persistence is requested when supported. Settings can export and
  restore a JSON recovery backup; account and device pairing are presented
  separately from operational sync controls.

## Sample ledger

The optional web sample is fictional and deterministic within the web client.
It is not claimed to be byte-for-byte identical to the iOS generated demo.
Deterministic IDs make repeated web imports idempotent.

## Hosting

[`public/_headers`](public/_headers) supplies a baseline CSP and security headers
for hosts that support the common static-file convention. [`public/_redirects`](public/_redirects)
adds the SPA fallback. Configure equivalent headers and fallback explicitly when
using a host that ignores these files.
