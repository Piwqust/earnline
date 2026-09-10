# earn›line

**A calm, native income ledger for independent work — built first for iPhone.**

[![CI](https://github.com/Piwqust/earnline/actions/workflows/ci.yml/badge.svg)](https://github.com/Piwqust/earnline/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/Piwqust/earnline?display_name=tag)](https://github.com/Piwqust/earnline/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-111111.svg)](LICENSE)

Add a line in seconds. See the month clearly. Keep the ledger on your phone,
then connect a private workspace only when you want your own devices to stay in
sync.

[Download](#download-earnline-121) · [Run from Xcode](#run-from-xcode) · [Why it feels right on iPhone](#why-it-feels-right-on-iphone) · [Contribute](CONTRIBUTING.md)

## Download Earnline 1.2.1

[**Open the latest GitHub release →**](https://github.com/Piwqust/earnline/releases/latest)

The release includes two unsigned IPA archives:

- `earnline-1.2.1-7-unsigned.ipa` — the primary iPhone app;
- `earnline-dev-1.2.1-7-unsigned.ipa` — a separate local-only development companion.

Unsigned IPA files are inspectable build artifacts, not one-tap App Store
installers. To use Earnline on your own iPhone today, build it from Xcode with
your Apple development team, or use a signing workflow that supports the app
and its extensions. The primary IPA includes a widget and Share extension;
re-signing must preserve the OAuth URL scheme and App Group entitlements.

Version 1.2.1 (build 7) restores the two-card header and inline composer, aligns
the Stats card with the earnings card, and adds safety snapshots, backup
previews, offline-session recovery, and system shortcuts.
See the [release notes](docs/RELEASE-1.2.1.md) for changes and verification limits.
The release includes `SHA256SUMS.txt` to verify both downloads.

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

## Run from Xcode

```bash
cd ios-app
xcodegen generate
open earnline.xcodeproj
```

Choose the `earnline` scheme, then run it on an iPhone simulator or a connected
iPhone. The [iOS README](ios-app/README.md) has the focused setup notes,
development companion details, and validation commands.

For agent-assisted iOS work, use Xcode 27 and its native Xcode MCP server as
the project baseline. Verify the app on an iPhone 17 with the iOS 27 runtime;
this does not change the app's iOS 26 deployment target.

## Repository guide

| Area | Role | Start here |
| --- | --- | --- |
| [`ios-app/`](ios-app) | **Primary product:** native SwiftUI income ledger | [iPhone guide](ios-app/README.md) |
| [`supabase/`](supabase) | Private sync and device-pairing infrastructure | [Backend guide](supabase/README.md) |
| [`docs/`](docs) | Operator runbooks and security records | [Documentation map](docs/README.md) |

## Privacy and operations

The repository contains no production credentials or ledger data. The longer
OAuth, device-pairing, security, and operations material is intentionally kept
out of the product introduction; operators can start in
[the documentation map](docs/README.md).

Earnline has no ads or analytics. Ledger data stays on the device in local mode. Signing in enables synchronization
with your private Supabase workspace. See the
[privacy statement](PRIVACY.md) for the exact boundary.

All screenshots above come from the running apps with fictional disposable
sample data. They contain no customer records, credentials, or stock mockups.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) before changing the shared sync
contract. The native iPhone app is the primary product surface.

## License

[MIT](LICENSE)
