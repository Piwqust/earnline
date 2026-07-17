# earn›line — iOS app

Native iOS 26 client for earn›line, built in SwiftUI with Apple's **Liquid Glass**
design system and SwiftData for offline‑first persistence. It syncs to the shared
Supabase backend described in the [repo root README](../README.md).

## ✦ Highlights

- 💬 **Smart composer** — build a line token by token: type the amount, **Return** → project, **Return** → task, **Return** commits. Pick an existing project or type a new one; date and hold‑until open as anchored popover tooltips.
- 🟢 **Three calm statuses** — **Paid** (gray, the default), **In progress** (orange), **Canceled** (red, excluded from totals).
- 🔢 **Rolling totals** — the summary total animates with an odometer‑style numeric roll as the displayed month changes under your scroll.
- 📐 **Responsive client rows** — the running total keeps the main currency full‑size; when space is tight it drops the secondary currency, then collapses **+ Line** to a single **+**.
- 💱 **Dual currency** — write in a primary currency, see a secondary converted value at an editable rate.
- 🔐 **Private account sync** — Google/GitHub OAuth resolves one private workspace; an owner can pair another device with a ten-minute, one-time QR code.

## ✦ Tech stack

| Layer | What |
| --- | --- |
| **UI** | SwiftUI (iOS 26) · Liquid Glass APIs |
| **Persistence** | SwiftData (`Client`, `Entry`, `Heading`) + sync tombstones |
| **State** | `@Observable` `AppModel` · `UserDefaults` currency settings |
| **Parsing** | custom, unit‑tested `LineParser` (amounts, currencies, hold dates, status marks) |
| **Sync** | Supabase Swift · OAuth owner / revocable paired-device membership · pinned via XcodeGen |
| **Project** | generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen) |

## ✦ Project structure

```
ios-app/
  earnline/
    Models/      Client, Entry, EntryStatus, Heading, SyncState   (SwiftData)
    Parsing/     LineParser, ParsedLine
    Theme/       Theme tokens, Color+Hex, CurrencyFormatter, DateFormat
    Sync/        SyncCoordinator, RemoteRecords, SupabaseProjectDefaults
    ViewModels/  AppModel  (state, currency, grouping & totals)
    Views/       LedgerView · SummaryPill · ClientChip · EntryRow · SmartComposer
                 MonthDivider · NewClientSheet · ClientDetailView · EditEntrySheet
                 SettingsView · EmptyStateView · GlassButtons · MoneyAmountText
    Util/        SampleData, IncomeLedgerImporter, Validation, DeterministicID, FlowLayout
  earnlineTests/ LineParserTests, ValidationTests, SyncModelTests
  project.yml
```

## ✦ Build & run

Run all commands from the `ios-app/` directory:

```bash
cd ios-app
xcodegen generate                                   # regenerate earnline.xcodeproj from project.yml
xcodebuild -scheme earnline \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' build
xcodebuild -scheme earnline \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' test
```

Open `ios-app/earnline.xcodeproj` in **Xcode 26** and run on an **iOS 26** simulator.
Launch arg `-demoComposer` opens the composer pre‑filled for the first client (handy for screenshots).

## ✦ Supabase

The production gate uses `ASWebAuthenticationSession` with
`com.earnline.app://auth/callback`, then resolves a Supabase workspace membership
before sync begins. Settings contains a compact **Account & devices** surface;
owners can inspect and revoke paired devices there. Pairing exchanges the
one-use QR token through a server function, so unrestricted anonymous Auth
sign-up stays disabled. The app lock remains independent from account
authentication. Test stays local-only.
The signed production build supplies `EARNLINE_SUPABASE_PRODUCTION_URL` and
`EARNLINE_SUPABASE_PRODUCTION_PUBLISHABLE_KEY` as build settings; the generated
Info.plist is the only client configuration source.
For a local Debug build, `Config/Local.xcconfig` optionally includes the ignored
`Config/Local.private.xcconfig`; populate that file from the local publishable
web configuration. It is intentionally never committed.
The tracked source must never contain a service-role key, OAuth client secret,
workspace ID, QR code, or real user identifier. Follow the staged setup and
private legacy-handoff instructions in [`../docs/AUTH_ROLLOUT.md`](../docs/AUTH_ROLLOUT.md).
