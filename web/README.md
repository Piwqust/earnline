# earn›line — web app

The browser client for earn›line, built with **React + Vite + TypeScript**. It shares the
same data model, sync engine, and Supabase wire format as the [iOS app](../ios-app) — so your
ledger stays in lock-step across phone and browser — but wears its own **desktop-first**
interface (sidebar · ledger · summary rail) built from web-native components, not a port of
the iOS screens.

## ✦ How it works

- **Local-first** — all data lives in IndexedDB (via [Dexie](https://dexie.org)),
  so the UI is instant and works offline. Components read it reactively with
  `useLiveQuery` (the web analog of SwiftData's `@Query`).
- **Full sync** — a faithful port of the iOS sync engine ([`src/sync`](src/sync)):
  push tombstones → push dirty rows → pull remote (last-write-wins on `updated_at`)
  → prune old tombstones. Triggered on load, window focus, reconnect, and 1.5s after
  each edit.
- **Live** — subscribes to Supabase **Realtime** (`postgres_changes`, filtered by
  `workspace_id`) so remote edits pull in without a refresh.
- **Identical wire format** — amounts as 2dp strings, days as `yyyy-MM-dd`,
  timestamps ISO-8601, snake_case columns. The [`LineParser`](src/domain/lineParser.ts),
  money, currency, and validation logic are direct ports of the Swift sources and are
  covered by the same unit-test cases (`*.test.ts`).

## ✦ Project structure

```
web/src/
  domain/    pure logic — types, lineParser, money, currency, validation, dateFormat, totals, deterministicId
  data/      Dexie db, repository (dirty/tombstone mutations), sample-ledger importer
  sync/      remoteRecords (DTO mappers), supabaseClient, syncCoordinator
  state/     settings (localStorage), store (sync orchestration + Realtime), data hooks
  ui/        screens (LedgerView · ClientDetailView · SettingsView · SmartComposer · EntryInspector …)
             components/  web-native kit (AppShell · Sidebar · RightRail · Dropdown · Dialog · Panel …)
             theme/       design tokens + stylesheets (tokens · base · shell · components · ledger · screens)
```

## ✦ Develop

```bash
cd web
npm install
npm run dev          # http://localhost:5173
npm test             # Vitest (parser / money / validation / wire-format parity)
npm run typecheck    # tsc --noEmit
npm run build        # type-check + production build
```

## ✦ Connect to Supabase

1. Apply [`../supabase/earnline_sync_schema.sql`](../supabase) to your Supabase project,
   replacing `your-workspace-id` with a private workspace identifier.
2. (Optional) Enable **Realtime** for the four `earnline_*` tables for live updates.
3. Open **Settings** in the app and enter the project **URL**, **publishable (anon)
   key**, and the same **workspace ID** you used in the iOS app. (You can also pre-fill
   these at build time via `.env` — see [`.env.example`](.env.example).)

> **Security:** the publishable/anon key is client-safe; the `workspace_id` is the only
> access gate and is visible in the browser bundle — the same low-security
> personal-sharing model as iOS. **Never** use a `service_role` key.

No data yet? Use **Settings → Import sample ledger** for the same demo data as iOS
(it uses matching deterministic IDs, so importing on both clients merges cleanly).
