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
- **Supabase Swift** for authenticated cloud sync, pinned through XcodeGen.
- **`@Observable`** app state + `@AppStorage`-backed currency settings.
- A custom, unit-tested **`LineParser`** powers the smart "type → chips" composer.

## Features
- **Chip + Return composer:** build a line token by token — type the amount and press **Return** to
  advance to the project, Return for the task, a final Return commits. Every token is a chip you can
  tap to jump back and edit; status and hold-date are chips you set directly. Values are limited and
  sanitized (amount range, field lengths), and chips wrap so nothing leaves the borders.
- **Continuous month scroll:** all months are one list separated by month dividers (each showing that
  month's subtotal); the summary pill tracks the top-most visible month as you scroll.
- **Add income** button on each client row; tap the client to open a per-client breakdown (by status
  & project).
- **Swipe a line** for Edit / Hide / Delete (custom swipe, since the ledger is a glass ScrollView).
- Dual currency: write in a primary currency, see a secondary converted value (editable rate).
- Status menus (logged → in-progress → paid), the New Heading / Project / Client glass menu, an empty
  state, and multi-month sample data on first launch.
- Bundled import of the original income ledger from `/Users/dameer/Desktop/earnline_income_db_1.txt`.
- Supabase email/password sign-in from Settings, local dirty-row sync, pull sync, and offline delete
  tombstones.

## Supabase setup
Run [supabase/earnline_sync_schema.sql](/Users/dameer/Desktop/code/earnline/supabase/earnline_sync_schema.sql)
in your Supabase SQL editor, then paste the Project URL and publishable key into Settings. The mobile
app never needs a service role key.

## Build & run
```bash
xcodegen generate                                   # regenerate the project from project.yml
xcodebuild -scheme earnline \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' build
xcodebuild -scheme earnline \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' test
```
Open `earnline.xcodeproj` in Xcode 26 and run on an iOS 26 simulator.
Verification launch args: `-demoComposer` opens the composer pre-filled; `-demoSwipe` opens the first
row's swipe actions.

## Layout
```
earnline/
  Models/      Client, Entry, EntryStatus, Heading   (SwiftData)
  Parsing/     LineParser, ParsedLine
  Theme/       Theme tokens, Color+Hex, CurrencyFormatter, DateFormat
  ViewModels/  AppModel  (state, currency, grouping & totals)
  Views/       LedgerView + SummaryPill, ClientChip, EntryRow, SmartComposer,
               MonthDivider, NewClientSheet, ClientDetailView, MonthSwitcherView,
               SettingsView, EmptyStateView, GlassButtons
  Util/        SampleData
earnlineTests/ LineParserTests
```
