# earn›line for the web

**An optional desktop companion to the iPhone-first Earnline app.** It exists
for people who specifically want a browser view of their private ledger; it is
not a replacement for the native iPhone workflow or the project's product
priority.

[Back to the iPhone-first project overview](../README.md) · [Primary iOS app](../ios-app/README.md)

## When the companion helps

- Review the same ledger at a desk with a persistent client sidebar and monthly
  summary rail.
- Keep a browser-local ledger useful during an offline session.
- Sign in only when connecting the private workspace shared with the iPhone
  app, and see connection or sync problems directly in Settings.

<table>
  <tr>
    <td align="center" width="50%">
      <img src="../docs/screenshots/readme/web-ledger.png" alt="Earnline optional desktop ledger with fictional sample data" width="360" />
      <br /><sub><b>Desktop ledger</b><br />A wider companion view for desk work.</sub>
    </td>
    <td align="center" width="50%">
      <img src="../docs/screenshots/readme/web-local-only.png" alt="Earnline web Settings with fictional local sync state" width="360" />
      <br /><sub><b>Visible sync state</b><br />Connection is clear instead of hidden.</sub>
    </td>
  </tr>
</table>

## Run locally

```bash
cd web
npm ci
npm run dev
```

Before shipping a web change, run:

```bash
npm test
npm run typecheck
npm run build
```

Keep the web client a companion: preserve the shared wire format and do not
make a normal Earnline workflow web-only when it belongs in the primary iPhone
app. The screenshots above were captured from the running app with disposable
fictional data.
