# earn›line

An **income-only notebook** for freelancers. Not a budget tracker, wallet, expense tracker, or CRM.
You write income as plain lines — and the app understands them.

```
+$240 LunaAI: 2 screens
⌛ +$140 LunaAI: Logotype hold until 14.07
✅ +$300 Studio X: Landing page
```

Each line is parsed into **amount · client · project · task · date · hold-until · status**, and totals
roll up automatically **by month, by client, and by status**.

## Design
Native iOS, built in Apple's **Liquid Glass** language (iOS 26) — a premium minimal notebook crossed
with a clean ledger. Source of truth: the earn›line Figma. Calm palette, SF Pro typography, real glass
materials, soft scroll edges, spring micro-interactions, and haptics.

## Stack
- **SwiftUI** (iOS 26) with the real Liquid Glass APIs (`glassEffect`, `GlassEffectContainer`,
  `buttonStyle(.glass)`, `scrollEdgeEffectStyle`).
- **SwiftData** for offline-first persistence (`Client`, `Entry`, `Heading`) plus sync tombstones.
- **Supabase Swift** for personal no-login cloud sync, pinned through XcodeGen.
- **`@Observable`** app state + `UserDefaults`-backed currency settings.
- A custom, unit-tested **`LineParser`** powers the smart "type → chips" composer.

## Features
- **Chip + Return composer:** build a line token by token — type the amount and press **Return** to
  advance to the project, Return for the task, a final Return commits. The amount, project, status,
  date, and hold-date are chips you set directly. The **project chip** lets you pick an existing
  project or type a new one; the **date** and **hold-until** open as anchored popovers (tooltips).
  Values are limited and sanitized (amount range, field lengths). The composer animates open as its
  own row beneath the client.
- **Statuses:** most income you add is already paid, so **Paid** is the calm default (gray
  `checkmark.circle.fill`). Lines that still need work show **In progress** (orange `clock.fill`),
  and ones that fell through show **Canceled** (red `xmark.circle.fill`).
- **Responsive client row:** the running total keeps the **main currency at full size**; if space is
  tight it drops the secondary-currency value, and if it's still tight the **+ Add Income** button
  collapses to a single **+**.
- **Continuous month scroll:** all months are one list separated by month dividers (each showing that
  month's subtotal); the summary pill tracks the top-most visible month as you scroll.
- **Per-client detail:** tap a client to open a breakdown by status & project.
- **Line actions:** swipe a row for Edit / Hide / Delete, or press-and-hold for a rich preview card
  with Edit, a Status picker, and Delete. **Deleting always asks for confirmation** (red, irreversible).
- **Dual currency:** write in a primary currency, see a secondary converted value (editable rate).
- **First-run data:** a bundled sample ledger is parsed in on first launch so the app isn't empty.
- **Sync:** Supabase personal-workspace sync from Settings — local dirty-row push, pull sync, and
  offline delete tombstones.

## Supabase setup
The app ships with the project URL and a **publishable** mobile key (safe to embed in a client; access
is gated by Row Level Security), so Settings is pre-filled. It syncs directly to the fixed
`earnline-personal` workspace with no app login — the app never needs a Postgres password or service
role key. The SQL history is mirrored under [`supabase/migrations`](supabase/migrations), with a
one-shot current schema at [`supabase/earnline_sync_schema.sql`](supabase/earnline_sync_schema.sql).

To connect the folder with the Supabase CLI:
```bash
supabase login
supabase init
supabase link --project-ref qpjfaapipwjultzvuxrm
```

## Build & run
This project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen):
```bash
xcodegen generate                                   # regenerate earnline.xcodeproj from project.yml
xcodebuild -scheme earnline \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' build
xcodebuild -scheme earnline \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' test
```
Open `earnline.xcodeproj` in Xcode 26 and run on an iOS 26 simulator.
Launch arg `-demoComposer` opens the composer pre-filled for the first client (handy for screenshots).

## Layout
```
earnline/
  Models/      Client, Entry, EntryStatus, Heading, SyncState   (SwiftData)
  Parsing/     LineParser, ParsedLine
  Theme/       Theme tokens, Color+Hex, CurrencyFormatter, DateFormat
  Sync/        SyncCoordinator, RemoteRecords, SupabaseProjectDefaults
  ViewModels/  AppModel  (state, currency, grouping & totals)
  Views/       LedgerView + SummaryPill, ClientChip, EntryRow, SmartComposer,
               MonthDivider, NewClientSheet, ClientDetailView, EditEntrySheet,
               SettingsView, EmptyStateView, GlassButtons
  Util/        SampleData, IncomeLedgerImporter, Validation, DeterministicID, FlowLayout
earnlineTests/ LineParserTests, ValidationTests
supabase/      schema + migrations
```
