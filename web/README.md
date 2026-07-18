# earn›line for the web

The desktop-first view of the same income ledger: a sidebar for clients, a
readable ledger in the middle, and a summary rail for the month.

![The desktop ledger with fictional local sample data](../docs/screenshots/readme/web-ledger.png)

## What it does

- Keeps a local browser ledger so entry remains useful offline.
- Makes month, client, project, and payment state easy to scan.
- Connects to a private workspace only after sign-in, then synchronizes with
  the iPhone app.
- Shows connection and sync state in Settings instead of hiding a problem.

![Web settings showing the local development sync state](../docs/screenshots/readme/web-local-only.png)

## Run locally

```bash
cd web
npm ci
npm run dev
```

Use `npm test`, `npm run typecheck`, and `npm run build` before shipping a web
change. The screenshots above were captured from the running app with
disposable fictional data.
