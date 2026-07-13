# earn›line — web app

Desktop-first React client for the same personal, no-account Earnline ledger as
the native iOS app. IndexedDB is the local source of truth; a capability-protected
Edge Function is the production sync boundary.

## Local development

```bash
cd web
npm ci
npm run dev
npm test
npm run typecheck
npm run build
```

The production browser never receives the database workspace ID, an anon key,
or a service/secret key. `VITE_EARNLINE_SYNC_ENDPOINT` is public. A high-entropy
per-browser connection capability is entered once under **Settings → Advanced sync
setup** and stored only in that browser. This preserves the product's no-login,
no-password model without pretending that a value embedded in JavaScript is a
secret.

Direct Supabase mode exists only in Vite development builds for local debugging.
Production builds fail closed unless a proxy connection was validated.

## Deploy production sync

The function in [`../supabase/functions/earnline-sync`](../supabase/functions/earnline-sync)
uses `@supabase/server` with `auth: "none"`; platform JWT verification is disabled
in [`../supabase/config.toml`](../supabase/config.toml) because the handler verifies
its own capability before any database operation. The Supabase secret key stays
server-side in the automatically provisioned function environment.

1. Link the correct Supabase project and apply migrations:

   ```bash
   supabase link --project-ref YOUR_PROJECT_REF
   supabase db push
   ```

   `EARNLINE_WORKSPACE_ID` in the next step must exactly match the private
   workspace value already enforced by the database CHECK constraints and RLS
   policies. On a brand-new project, generate that value first and replace the
   `your-workspace-id` bootstrap placeholder before applying the initial schema.
   Keep the rendered, environment-specific SQL out of source control.

2. Generate a capability locally and store only its SHA-256 hash on the server:

   ```bash
   CAPABILITY="$(openssl rand -base64 48 | tr -d '\n')"
   CAPABILITY_HASH="$(printf %s "$CAPABILITY" | shasum -a 256 | awk '{print $1}')"
   SCOPE_SALT="$(openssl rand -hex 32)"
   supabase secrets set \
     EARNLINE_WEB_CAPABILITY_HASHES="$CAPABILITY_HASH" \
     EARNLINE_SCOPE_SALT="$SCOPE_SALT" \
     EARNLINE_WORKSPACE_ID="YOUR_PRIVATE_WORKSPACE_ID" \
     EARNLINE_ALLOWED_ORIGINS="https://your-web-app.example"
   ```

3. Deploy and set the public endpoint in the web host:

   ```bash
   supabase functions deploy earnline-sync
   # web host variable:
   # VITE_EARNLINE_SYNC_ENDPOINT=https://YOUR_PROJECT_REF.supabase.co/functions/v1/earnline-sync
   ```

4. Enter the un-hashed `$CAPABILITY` once in that trusted browser. Generate a
   separate capability for another browser, append its hash to the comma-separated
   `EARNLINE_WEB_CAPABILITY_HASHES` secret, and redeploy. Do not put raw capabilities
   in `.env`, CI variables prefixed with `VITE_`, URLs, screenshots, or commits.

The function allowlists tables and columns, overwrites every incoming
`workspace_id`, caps batches, keeps responses free of the real workspace ID,
and uses the server client only after constant-time capability verification.
The origin allowlist is defense in depth; the high-entropy capability remains
the authorization boundary for non-browser callers.

## Sync guarantees

- Pull-before-push conflict detection prevents a reconnecting browser from
  silently overwriting newer iPhone changes.
- A conflict stops before either version is changed; Settings offers explicit
  cloud or browser resolution.
- Tombstones are server-timestamped, retained, and replayed in full. A device
  that was offline for months cannot miss a deletion because of a cursor or
  retention window.
- Each validated connection has a separate IndexedDB database and cursor.
- Web Locks plus an atomic IndexedDB lease prevent simultaneous tab sync passes;
  BroadcastChannel propagates completion state.
- Proxy mode polls while visible and also syncs on focus/reconnect. Development
  direct mode additionally reports Supabase Realtime channel state. Polling is
  required for correctness because Realtime DELETE filters are not sufficient.
- Browser persistence is requested when supported. Settings can export and
  restore a JSON recovery backup.

## Sample ledger

The optional web sample is fictional and deterministic within the web client.
It is not claimed to be byte-for-byte identical to the iOS generated demo.
Deterministic IDs make repeated web imports idempotent.

## Hosting

[`public/_headers`](public/_headers) supplies a baseline CSP and security headers
for hosts that support the common static-file convention. [`public/_redirects`](public/_redirects)
adds the SPA fallback. Configure equivalent headers and fallback explicitly when
using a host that ignores these files.
