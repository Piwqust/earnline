# earn›line

**A calm, native income ledger for independent work — built first for iPhone.**

Add a line in seconds. See the month clearly. Keep the ledger on your phone,
then connect a private workspace only when you want your own devices to stay in
sync.

[Run the iPhone app](#run-on-an-iphone) · [Why it feels right on iPhone](#why-it-feels-right-on-iphone) · [Optional web companion](#the-web-is-optional) · [Contribute](CONTRIBUTING.md)

## A quick tour

<table>
  <tr>
    <td align="center" width="33.33%">
      <img src="docs/screenshots/readme/ios-ledger.png" alt="Earnline ledger on iPhone with fictional income entries" width="220" />
      <br /><sub><b>See the month</b><br />Amounts, work, dates, and status stay easy to scan.</sub>
    </td>
    <td align="center" width="33.33%">
      <img src="docs/screenshots/readme/ios-composer.png" alt="Earnline income composer on iPhone with fictional data" width="220" />
      <br /><sub><b>Add a line quickly</b><br />Start with the work; add the useful details without a form.</sub>
    </td>
    <td align="center" width="33.33%">
      <img src="docs/screenshots/readme/ios-filters.png" alt="Earnline native search and Filters control on iPhone" width="220" />
      <br /><sub><b>Find it naturally</b><br />Search words, then narrow by date, client, project, or status.</sub>
    </td>
  </tr>
</table>

## Why it feels right on iPhone

Earnline is for the small moments between client work: logging an invoice,
checking what is still in progress, or remembering why a total changed. The
native iPhone app is the product's home, so its flow stays direct, familiar,
and deliberately free of admin-dashboard noise.

- **Write, do not fill out a spreadsheet.** The composer keeps the essential
  information together: amount, client, project, task, date, and payment state.
- **Read the ledger at a glance.** Money leads each row; work, date, and status
  remain clear without turning the screen into a wall of cards.
- **Use the gestures and controls an iPhone already teaches.** Native search,
  filters, menus, sheets, keyboard flow, and swipe actions keep everyday work
  fast.
- **Stay useful offline.** SwiftData is the local source of truth, so a weak
  connection does not interrupt a workday.
- **Keep sync personal.** Start locally with no cloud account, or sign in and
  connect a private workspace to synchronize your own devices. Paired devices
  can be reviewed and revoked from Settings.

## Run on an iPhone

```bash
cd ios-app
xcodegen generate
open earnline.xcodeproj
```

Choose the `earnline` scheme, then run it on an iPhone simulator or a connected
iPhone. The [iOS README](ios-app/README.md) has the focused setup notes,
development companion details, and validation commands.

## The web is optional

The React app is a desktop-first companion for people who specifically want a
browser view of the same private ledger. It is useful at a desk, but it does
not set the product's interaction direction or replace the iPhone experience.

[Open the web companion guide →](web/README.md)

## Repository guide

| Area | Role | Start here |
| --- | --- | --- |
| [`ios-app/`](ios-app) | **Primary product:** native SwiftUI income ledger | [iPhone guide](ios-app/README.md) |
| [`web/`](web) | Optional desktop companion | [Web guide](web/README.md) |
| [`supabase/`](supabase) | Private sync and device-pairing infrastructure | [Backend guide](supabase/README.md) |
| [`docs/`](docs) | Operator runbooks and security records | [Documentation map](docs/README.md) |

## Privacy and operations

The repository contains no production credentials or ledger data. The longer
OAuth, device-pairing, security, and operations material is intentionally kept
out of the product introduction; operators can start in
[the documentation map](docs/README.md).

All screenshots above come from the running apps with fictional disposable
sample data. They contain no customer records, credentials, or stock mockups.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) before changing the shared sync
contract. iOS is the primary product surface; web and Supabase changes follow
when a feature needs them.

## License

[MIT](LICENSE)
