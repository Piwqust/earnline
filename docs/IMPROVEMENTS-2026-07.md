# Earnline — enhancement proposals, July 2026

Companion to [`AUDIT-2026-07.md`](AUDIT-2026-07.md). That document covered
**defects** — correctness, performance, backend hygiene. This one covers
**what the app could become**: product gaps, absent platform surfaces, and
interaction opportunities.

Scope: `ios-app/` only. Nothing here is a bug; the app works. Everything here
is a deliberate "not yet."

Starting position, so the recommendations are calibrated fairly:

- ~20.6k lines of Swift across 82 files, 191 unit tests, 24 UI tests
- SwiftLint clean at error level (52 warnings, all cosmetic)
- Dynamic Type handled properly (`Theme.swift` `ScaledFont` — every size scales
  through `UIFontMetrics`, not frozen `.system(size:)`)
- VoiceOver labels in 26 files, `ContentUnavailableView` in 10, Reduce Motion
  honored app-wide via a single `.transaction` interceptor
- Privacy manifest complete and honest; no required-reason API is used
  undeclared
- Localized to English + Russian (332 keys, 330 translated)

This is a well-built app. The recommendations below are mostly about **reach**,
not repair.

---

## Priority summary

| # | Proposal | Impact | Effort | Type |
|---|---|---|---|---|
| **1** | Freeze the exchange rate per entry | **High — ledger integrity** | S | Correctness-adjacent |
| **2** | App Intents (Siri / Shortcuts / Spotlight / Action button) | **High** | M | Platform |
| **3** | Home & Lock Screen widgets | **High** | M | Platform |
| **4** | Single-line natural-language entry in the composer | **High** | S | Interaction |
| **5** | Actionable notifications ("Mark paid" from the banner) | Medium-high | S | Platform |
| **6** | Tax set-aside | Medium-high | M | Product |
| 7 | Leading swipe → mark paid | Medium | XS | Interaction |
| 8 | Backup story for guest ledgers | Medium | M | Product |
| 9 | Recurring / retainer lines | Medium | M | Product |
| 10 | Spotlight indexing of entries and clients | Medium | S | Platform |
| 11 | Year in review | Medium | M | Product |
| 12 | Background sync refresh | Low-medium | S | Platform |
| 13 | `performAccessibilityAudit()` in UI tests | Low-medium | XS | Process |
| 14 | Handoff to the web companion | Low | S | Platform |
| 15 | iPad / landscape | Low | M | Platform |
| 16 | Onboarding video is 15 MB of the bundle | Low | XS | Process |
| 17 | More than two convertible currencies | Low | M | Product |

Effort: XS = under an hour · S = a day · M = a few days.

---

## 1. Freeze the exchange rate per entry

**This is the one item here I would treat as close to a bug.**

`AppModel.rate` (`ViewModels/AppModel.swift:139`) is a single global `Double`.
`CurrencyConverter.toBase` (`Util/CurrencyConverter.swift:30`) applies it to
every entry regardless of the entry's date, and `Entry` stores no rate of its
own (`Models/Entry.swift`).

So: a user with USD base and RUB secondary logs ₽100 000 in January when the
rate is 90. In July they tap **Fetch current rate** in Settings, which writes
95. January's total silently changes from $1 111 to $1 053 — and so does every
month, every chart point, every already-shared report card, and the year-to-date
figure.

`LedgerView.PricingRevision` (`Views/LedgerView.swift:107`) makes this explicit:
a rate change is a first-class reason to rebuild the entire ledger snapshot.
The machinery is correct; the semantics are the problem. **A ledger is a
record of what happened. Re-pricing history is the one thing it must not do.**

`ExchangeRateService`'s doc comment already gestures at this care — *"Never
called automatically: whatever the user types stays authoritative"*
(`Util/ExchangeRateService.swift:5`). Per-entry freezing is the same instinct,
carried one step further.

**Recommendation.** Add `baseAmountSnapshot: Decimal?` (or `rateAtEntry:
Double?`) to `Entry`, written at commit time from the rate in force. Totals read
the snapshot; the live rate is used only for entries that lack one and for
*preview* of a new line. Backfill existing rows with the current rate in a
migration — imperfect, but it freezes the drift at one known point instead of
letting it continue.

Wire-format note: this needs a column on the sync side and a matching change in
`web/src/sync/`, so it belongs with the R2 conformance work the audit deferred.
A local-only interim version (`syncState` untouched, column nullable) is
possible if you want the integrity fix before the protocol change.

**Second-order benefit:** it fixes reports. `ReportSnapshotBuilder` renders PNG
cards the user shares with clients. Today, re-sharing the same month after a
rate refresh produces a different number on a card that claims to describe a
fixed past period.

---

## 2. App Intents — the single highest-leverage platform addition

Zero files import `AppIntents`. For an app whose entire product thesis is *"add
a line in seconds"*, this is the biggest gap on the list.

One `AppIntent` in iOS 26 lights up, from the same definition: Siri, the
Shortcuts app, Spotlight's action row, the Action button, Control Center, and
widget tap targets. ([Get to know App Intents,
WWDC25](https://developer.apple.com/videos/play/wwdc2025/244/); [The iOS 26
Widget Surface: One App Intent, Many
Places](https://blakecrosley.com/blog/ios-26-widget-and-control-surface))

The app's verbs map onto intents unusually cleanly:

| Intent | Phrase | Backing code that already exists |
|---|---|---|
| `LogIncomeIntent` | "Log 240 dollars from Acme in Earnline" | `SmartComposer.commit()` |
| `MarkPaidIntent` | "Mark the Northstar line paid" | `EntryStatus` cycling in `EntryRow` |
| `PendingTotalIntent` | "How much is Earnline waiting on?" | the scoped in-progress fetch in `AppModel.refreshPendingReminders` (`AppModel.swift:631`) |
| `MonthEarnedIntent` | "What did I earn this month?" | `InsightsDashboardSnapshot` |

`Client` and `Entry` become `AppEntity`s with an `EntityQuery` — which is also
what makes #10 (Spotlight) nearly free once this exists.

iOS 26 adds **interactive snippets**, so `PendingTotalIntent` can return a small
live card with "Mark paid" buttons directly in the Siri/Spotlight surface,
rather than a spoken sentence. ([App Intents Interactive Snippets in iOS
26](https://superwall.com/blog/app-intents-interactive-snippets-in-ios-26))

**Start with `LogIncomeIntent` alone.** It is the app's core verb, it is the
one users will bind to the Action button, and it is a prerequisite for the
widget in #3.

---

## 3. Widgets

No `WidgetKit` target exists. Two are obvious, and both are mostly assembly of
things already written:

**Home Screen, small/medium — "Earned in July".** The exact content of the
existing summary pill (`Views/LedgerSummaryHeader.swift`) — month total, plus a
sparkline on medium from `InsightsDashboardSnapshot.monthlyIncome`. Tapping
opens the app; a corner `+` button fires `LogIncomeIntent` from #2 without
launching.

**Lock Screen, accessory rectangular — pending.** "3 lines · $1 240 waiting",
straight from the `pendingCount` the ledger snapshot already computes
(`Views/LedgerView.swift:142`). For someone chasing invoices this is the single
most glanceable fact the app owns.

The Mobbin lock-screen references — [Granola](https://mobbin.com/screens/31f7fe7c-6dba-4732-b02a-7ec9ed9aa195),
[Journal](https://mobbin.com/screens/19223d1d-da28-4082-adb1-5771944b5d47),
[yope](https://mobbin.com/screens/8a1da028-b94e-456a-aa74-749831b3ced6) — all
converge on the same shape: one number or one prompt, one tap to act. None of
them try to be a dashboard on the Lock Screen. Earnline should not either.

**Implementation note.** Widgets need the store in an App Group, and
`WorkspaceStore.localStoreName` (`earnlineApp.swift:326`) currently builds
per-workspace names in the app container. The widget also needs to pick the
*active* workspace, which lives in `UserDefaults`. Plan for a shared suite —
this is the real cost of the feature, not the SwiftUI.

---

## 4. Let the composer accept one typed line

`LineParser` is 384 lines of careful work — amounts, currencies, `project:
task` splitting, status words, hold dates, a month-name map — with 34 unit
tests, the largest test file in the project.

**The primary composer does not use it.** `SmartComposer` has an `initialText`
parameter that runs `LineParser.parse` (`Views/SmartComposer.swift:343`), and
**no caller in the app ever passes it.** The parser's only production reach is
`PasteLinesSheet` — a bulk-paste path most users will never open.

So the app's fastest input method exists, is tested, and is unreachable.

**Recommendation.** Add a single-field mode to the composer: type
`+240 Acme: two homepage concepts hold until 25.08`, hit return, get a
fully-formed line. Keep the chip UI as the default and as the correction
surface — parse into the chips so the user sees what was understood and can fix
one part without retyping. The README already sells this idiom
(*"Add a line in seconds"*), and `README.md`'s own example line is written in
exactly this syntax.

This is also what makes `LogIncomeIntent` (#2) trivially good: Siri hands you a
string, and the parser is already the thing that turns strings into entries.

**Effort is genuinely small** — the parse call is written, the chips are
bindable state, and the tests exist. This is mostly UI plumbing and a mode
toggle.

---

## 5. Actionable notifications

`PendingNotifications` (`Util/PendingNotifications.swift`) is nicely built —
recompute-only reconciliation, pure `desiredRequests` under test, permission
requested in context rather than at launch. But:

- No `UNNotificationCategory` / `UNNotificationAction` is registered anywhere
- No `UNUserNotificationCenterDelegate` exists

The body of the reminder literally asks a yes/no question — *"…is due — mark it
paid?"* (`PendingNotifications.swift:41`) — and then gives the user no way to
answer it. Tapping the banner opens the ledger at the top, not at the line.

**Recommendation.** Two things, both small:

1. A category with **Mark paid** and **Snooze a week** actions. `MarkPaidIntent`
   from #2 is the handler for the first; the second re-writes `holdUntil`, which
   `sync` already reconciles idempotently.
2. A delegate that routes the tap to the entry. `LedgerRoute` /
   `LedgerSheetRoute` (`Views/LedgerView.swift:56`) are already typed routes —
   this is a matter of pushing one, not inventing navigation.

---

## 6. Tax set-aside

The one product feature I would argue *belongs* in an income-only ledger.

Earnline is deliberately not a budget app — `PRODUCT.md` is explicit, and the
anti-references list is right. But "how much of this is actually mine?" is not
budgeting. It is a property of income, and it is the thing independent
professionals get wrong most often. Every 2026 roundup of freelancer tooling
leads with tax handling for this reason ([Best Apps For Freelancers And The
Self-Employed In 2026](https://welovesalt.com/insights/best-apps-freelancers)).

**The minimal version fits the existing model with no new screen:** one
percentage in Settings, and a second line under the month total —
`$2 555 earned · $639 set aside · $1 916 yours`. Optionally per-client, since
rates differ by jurisdiction and contract type.

Explicitly *not* recommended: expense tracking, deduction categories, receipt
scanning, mileage. Those are a different product and would break the
"quiet ledger" north star in `DESIGN.md`. The set-aside number is a lens on
income the user already recorded — nothing new to enter, no new discipline
required.

---

## 7. Leading swipe → mark paid

`swipeActions` appears in exactly two files, and on the ledger row it is
trailing-edge only, `allowsFullSwipe: false` (`Views/LedgerRowsView.swift:74`).

Marking a line paid currently costs: tap the status dot → menu opens → pick
Paid. Three interactions, one of them a menu, for the single most repeated
action in the app.

A leading swipe with `allowsFullSwipe: true` makes it one gesture. Mail's
idiom, and the ledger row is already the right shape for it. The status cycle
(`EntryStatus.next`) means you could equally bind it to "advance status," but
"mark paid" is the action people actually want — `.paid` is already documented
as the calm default state.

**Effort: under an hour.** Highest ratio of benefit to work on this list.

---

## 8. Backup story for guest ledgers

"Continue without an account" creates a guest ledger in a local SwiftData file
that **never syncs** (`AppModel+Auth.swift:193`, `GuestLedgerMigration.swift:7`).
The file is not in iCloud, not in an App Group, and not backed by CloudKit
(`WorkspaceStore.init` builds a plain `ModelConfiguration`,
`earnlineApp.swift:309`).

If a guest user loses or wipes the phone, the ledger is gone. CSV export exists
(`Views/CSVTransferView.swift`) but is manual and undiscoverable at the moment
it matters. (`GuestLedgerMigration` covers the guest → signed-in upgrade path,
not device loss.)

The design is defensible — the whole point of guest mode is that nothing leaves
the device, and `GuestLedgerMigration` handles the eventual upgrade carefully.
But "private" and "unrecoverable" got conflated, and the user is never told.

**Options, in order of how much I'd recommend them:**

1. **Say so.** One line at the guest-mode choice and one row in Settings:
   *"This ledger lives only on this iPhone. It is included in encrypted iPhone
   backups, but it is not synced or recoverable if the device is lost."*
   Honest, costs nothing, and may be sufficient.
2. **Periodic CSV nudge.** After N entries or N days without an export, a quiet
   Settings badge. Fits the app's restraint.
3. **CloudKit private database for guest stores.** `ModelConfiguration` supports
   `cloudKitDatabase:`, so this is a small change mechanically — but it means a
   second sync engine alongside Supabase, and the audit already flags divergence
   between the two you have (R2). I would not do this without a strong reason.

---

## 9. Recurring / retainer lines

Every entry is typed by hand. For an independent professional, a large share of
income is the same amount, from the same client, every month — a retainer.

The data model needs almost nothing: a `recurrence` on `Entry` (or a small
`RecurringTemplate` model) plus a materialization pass. `MonthReview` already
demonstrates the pattern for a deterministic, sync-safe derived row —
`DeterministicID.uuid(...)` keyed on the month means two devices offline
generate the *same* id and converge instead of duplicating
(`Models/MonthReview.swift:56`). A recurring line keyed on
`template-id + month` behaves identically.

Materialize as `.inProgress` on the 1st, so it lands in Pending and the user
confirms it rather than the ledger asserting income that has not arrived. That
keeps the trust property intact: the ledger only ever contains things a human
affirmed.

---

## 10. Spotlight indexing

No `CoreSpotlight`. The app has a genuinely good in-app search
(`Util/EntrySearch.swift`, token filters, 16 tests) that stops at the app
boundary.

Once `Entry` and `Client` are `AppEntity`s for #2, adopting `IndexedEntity` is
close to free, and "Acme" typed into the iPhone's own search finds the client
and its lines. For an app people open in ten-second bursts, removing the
launch-then-search step is worth more than it sounds.

---

## 11. Year in review

`MonthReview` already implements a soft month close with a note, and
`ReportCardRenderer` produces shareable PNG cards. The year is the obvious
missing scope — and it is the moment people actually want to share.

The Mobbin references converge on a recognizable shape: one hero number, a
twelve-month bar, a top-N breakdown, one share button.
[Hyundai Card](https://mobbin.com/screens/63810856-f8ec-4c79-b521-cbe260eba9e8)
and [CRED](https://mobbin.com/screens/7f33e880-f2cb-450b-a1bd-90def15a9e64) are
the cleanest of them.

`ReportScope` already has a `.isMonth` discriminator, so a `.year` case is a
natural extension rather than a new subsystem. Worth timing for early January.

---

## 12. Background sync refresh

No `BGTaskScheduler`. Sync runs on foreground activation
(`earnlineApp.swift:247`), on realtime echo, and on debounce after an edit.

A single `BGAppRefreshTask` means opening the app shows current data instead of
data plus a spinner. Small, and it makes multi-device pairing — which the app
invested real work in (`Views/PairedDevicesView.swift`, device revocation, the
pairing RPCs) — feel like it works rather than like it catches up.

---

## 13. `performAccessibilityAudit()` in the UI tests

Three UI test files, 24 tests, and none call
`XCUIApplication.performAccessibilityAudit()`. One line per screen catches
contrast failures, sub-44pt hit targets, missing labels, and clipped Dynamic
Type — automatically, forever.

`PRODUCT.md` commits to exactly these properties ("44-point minimum touch
targets", "Dynamic Type", "VoiceOver labels"). Right now that commitment is
maintained by discipline. This makes it maintained by CI.

**Effort: minutes.** Add it to the existing `EarnlineUITests` smoke paths.

---

## 14. Handoff to the web companion

No `NSUserActivity`. The web client exists and syncs the same ledger, but
moving between them means re-finding your place.

`.userActivity` on the ledger and client-detail views, advertising a URL the web
app resolves, gives you Handoff on the Mac's Dock and in the app switcher. Low
effort, and it makes the two-client story feel intentional rather than parallel.

---

## 15. iPad and landscape

`TARGETED_DEVICE_FAMILY: "1"` and portrait-only (`project.yml:78`,
`Resources/Info.plist`). iPhone-first is a stated product decision and I would not
overturn it.

But "Designed for iPad" is close to free given the app is already a
`NavigationStack` with sheets, and landscape on iPhone costs only checking that
the ledger rows and the composer survive the rotation. Worth doing when
convenient; not worth a sprint.

---

## 16. The onboarding video is 15 MB

`Resources/earnline-onboarding.mov` is 15.3 MB in a bundle that is otherwise
Swift. That is likely the single largest contributor to download size for an
app whose entire promise is lightness.

Re-encode as HEVC at the display resolution the auth backdrop actually uses
(`Views/Auth/AuthBackdropVideo.swift`). Typically a 3–5× reduction with no
visible difference at that size. Ten minutes with `ffmpeg`.

---

## 17. More than two convertible currencies

`CurrencyConverter` supports exactly base + secondary
(`conversionRate`, `Util/CurrencyConverter.swift:20`). A third currency returns `.zero` from
`toBase` and is excluded from consolidated totals.

To the codebase's credit this is handled *visibly*, not silently: the entry
renders in orange with a VoiceOver hint, and Insights shows a count of excluded
lines (`Views/InsightsView.swift:146`). That is the right behavior for the
constraint.

But five supported codes with two convertible at a time is a low ceiling for
"independent professional," who is the archetypal person invoicing across
borders. A rate table (`[String: Double]` keyed by code) rather than a scalar is
the same shape of change everywhere it is read — and combined with #1's
per-entry freezing, the historical-accuracy problem is solved at the same time.

Lower priority because the current failure mode is honest. Sequence it after #1.

---

## Not recommended

Worth writing down so they do not get proposed later:

- **Expense tracking, receipts, mileage, deductions.** A different product.
  `PRODUCT.md`'s anti-references are correct.
- **Invoicing / payment collection.** Enormous scope (PDF generation, payment
  rails, tax jurisdictions, dunning) and it turns a calm notebook into an admin
  console — the exact thing `DESIGN.md` names as the failure mode.
- **CloudKit as a second sync engine.** See #8. The audit's R2 already flags that
  two implementations of one protocol drift; three would be worse.
- **A tab bar.** The bottom bar with `…` / search / `+` is the iOS 26 Notes and
  Mail idiom, correctly applied. Four tabs would be a downgrade for an app with
  one primary surface.

---

## Suggested sequencing

**Ledger integrity first**, because everything downstream quotes those numbers:
**#1**, then **#17** as its natural completion.

**Then the two cheap interaction wins** while the platform work is planned:
**#7** (an hour), **#13** (minutes), **#16** (ten minutes), **#4** (a day, and
it unblocks #2).

**Then the platform arc**, in dependency order — it is one arc, not five
features: **#2** App Intents → **#3** widgets → **#10** Spotlight → **#5**
notification actions.

**Then product**, informed by what actual users ask for: **#6** tax set-aside,
**#9** recurring, **#11** year in review.

**#8** (the guest-backup disclosure, option 1 only) should be done before the
App Store release regardless of where it falls in this order — it is a one-line
honesty fix on a data-loss scenario.
