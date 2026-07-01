<div align="center">

# earn›line

**An income‑only notebook for freelancers — now on iOS *and* the web.**
Jot income the way you'd type it in Notes — earn›line parses every line into a clean, self‑totalling, cloud‑synced ledger that stays in lock‑step across your phone and your browser.

<br>

![iOS 26](https://img.shields.io/badge/iOS-26-000000?style=for-the-badge&logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-6-F05138?style=for-the-badge&logo=swift&logoColor=white)
![React](https://img.shields.io/badge/React-Vite_·_TS-61DAFB?style=for-the-badge&logo=react&logoColor=black)
![Supabase](https://img.shields.io/badge/Supabase-sync-3FCF8E?style=for-the-badge&logo=supabase&logoColor=white)

<br>

<table>
  <tr>
    <td><img src="docs/screenshots/ledger.svg" width="320" alt="The earn›line ledger"></td>
    <td><img src="docs/screenshots/composer.svg" width="320" alt="The earn›line composer"></td>
  </tr>
  <tr>
    <td align="center"><b>The ledger</b><br><sub>months · clients · color‑coded statuses</sub></td>
    <td align="center"><b>The composer</b><br><sub>type → chips → commit</sub></td>
  </tr>
</table>

</div>

---

## ✦ What it is

earn›line is **income‑only** — deliberately *not* a budget app, wallet, expense tracker, or CRM. You write what you earned as plain lines, and the app understands them:

```
+$240 Acme: 2 screens
⌛ +$140 Acme: Logotype hold until 14.07
✅ +$300 Studio X: Landing page
```

Every line is parsed into **amount · client · project · task · date · hold‑until · status**, and totals roll up automatically **by month, by client, and by status**.

## ✦ This is a monorepo

| App | Path | Stack |
| --- | --- | --- |
| 📱 **iOS** | [`ios-app/`](ios-app) | SwiftUI (iOS 26) · Liquid Glass · SwiftData · Supabase Swift |
| 🌐 **Web** | [`web/`](web) | React · Vite · TypeScript · Dexie · supabase-js · desktop‑first UI |
| ☁️ **Backend** | [`supabase/`](supabase) | Shared Postgres schema + migrations (no app‑specific code) |

Both apps are **peers** of the same Supabase project: they write the same tables with the same conventions, so a line added on the phone shows up in the browser and vice‑versa.

The iOS app is a phone‑native SwiftUI experience; the **web app is desktop‑first**, with its own web‑native design system (sidebar · ledger · summary rail) rather than a port of the iOS screens. Only the presentation differs — the data model, sync engine, and wire format are shared.

## ✦ Full synchronization

There is no separate server — sync is a set of conventions over four Postgres tables (`earnline_clients`, `earnline_entries`, `earnline_headings`, `earnline_tombstones`), scoped by a `workspace_id`:

- **Personal, no‑login** — both clients connect with the project's *publishable* key and a shared workspace ID (entered in each app's Settings). No accounts.
- **Offline‑first on both platforms** — iOS uses SwiftData, web uses Dexie/IndexedDB. Edits apply instantly and queue for sync.
- **Last‑write‑wins** on `updated_at`, with **tombstones** so deletes propagate.
- **Live** — the web app additionally subscribes to Supabase Realtime, so remote changes appear without a manual refresh.

> **Security model:** the publishable/anon key is client‑safe; the `workspace_id` is the only access gate and is a low‑security personal‑sharing identifier. Never put a `service_role` key in either app.

## ✦ Repo structure

```
earnline/
  ios-app/     SwiftUI app  (Models · Parsing · Theme · Sync · ViewModels · Views · Tests)
  web/         React + Vite app  (domain · data · sync · state · ui)
  supabase/    shared Postgres schema + migrations
  docs/        screenshots
  .github/     CI workflow + CODEOWNERS
```

## ✦ Get started

- **iOS** — see [`ios-app/README.md`](ios-app/README.md)
- **Web** — see [`web/README.md`](web/README.md)
- **Backend** — apply [`supabase/earnline_sync_schema.sql`](supabase/earnline_sync_schema.sql) to your Supabase project, replacing `your-workspace-id` with a private workspace identifier, then enter the project URL, publishable key, and that workspace ID in each app's Settings.

## ✦ CI

[`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs two jobs: the iOS job regenerates the project with XcodeGen and runs `xcodebuild test`; the web job runs the Vitest suite and a production build.

## ✦ Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for the monorepo layout, per‑app dev commands, and the wire‑format contract both apps must uphold. Review ownership is declared in [`.github/CODEOWNERS`](.github/CODEOWNERS).

## ✦ License

Released under the [MIT License](LICENSE).

<div align="center"><sub>Built with SwiftUI, React, and one shared wire format. ✦</sub></div>
