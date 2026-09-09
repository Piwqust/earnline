# What's new

## September 5, 2026

### Reliability
- Money fields preserve pasted values and reject ambiguous fractions or amounts above the limit.
- Sync snapshots each batch consistently and checks cloud versions atomically before writing.
- Currency changes apply together with their rate; stale network responses cannot replace an edited rate.
- Text limits match the cloud’s Unicode contract without splitting emoji.
- GitHub sign-in uses the registered callback scheme even when a signing service changes the bundle identifier.

### Everyday use
- Sync status, errors, and recovery are available without Developer Mode.
- Large text uses a stacked composer and summary layout.
- Backup previews show the original and current currency settings.
- Added missing Russian interface and recovery messages.

## September 4, 2026

### Reliability
- The ledger summary now follows month boundaries consistently on iOS 26 and iOS 27, including long histories.
- Updates now discard the old Supabase placeholder saved by an earlier release, so the built-in account connection is restored without deleting the local ledger.

## September 3, 2026

### Reliability
- The Stats summary card opens Insights reliably on iOS 27 instead of sometimes accepting the tap without presenting the sheet.
- Amounts typed in the composer now parse the same way on a Russian (or any non-US) region setting, so `99.50` can no longer be read as `9950`.
- Settings’ pending-sync count now includes rows that have never been marked synced, matching what the next sync actually pushes.
- Importing a backup, on-device ledger, or sample ledger now rolls back if the copy fails, and a successful import refreshes the ledger immediately.
- Sync no longer crashes a pass when a project icon arrives from the cloud under a different id than this iPhone stored.
- Deleting a client now reports a save failure on the profile instead of returning to the ledger with the client still there and no explanation.
- CSV import now rejects names, tasks, and projects that the cloud would refuse, so one oversized spreadsheet cell cannot stall every later sync.
- Amounts typed in the composer and editor snap to cents before they are saved, matching the money format Earnline syncs.

### Ledger
- Event notes can be deleted with the same trailing swipe as income lines.

## August 1, 2026

### Reliability
- Ledger and Insights now surface local read failures instead of replacing a missing result with an empty ledger or zero count.
- Sync saves pending local edits before merging cloud data and detects workspace-profile conflicts before a currency change can overwrite a newer cloud value.
- Release configuration rejects secret Supabase keys, and exchange-rate requests now validate currency pairs, HTTP status, and timeouts.

## July 30, 2026

### Ledger
- The **Stats** card opens **Insights** again, while **Insights** remains available from the **…** menu. Long ledgers now track the visible month without measuring every row during scrolling.

## July 29, 2026

### Sync and account safety
- Ledger commands now use the navigation bar instead of the iOS 26 bottom
  toolbar, removing a system runtime hierarchy warning while retaining native
  menus and search.
- Importing an on-device ledger now also brings over month-close notes. If that older local copy cannot be read, Earnline shows the problem and leaves it untouched instead of pretending there is nothing to import.
- Project-icon checks now use a stable accessibility value across supported iOS versions.
- Device pairing can safely retry after an interrupted connection without creating a second device identity.
- Sign-in data now uses an explicit, device-only secure-storage policy. If iPhone Keychain cannot remove it during sign out, Earnline keeps the session visible and tells you to unlock the device and retry.

## July 28, 2026

### Getting started
- The first-run illustration now stays fixed behind the form when the keyboard opens, while the controls continue to move above the keyboard.
- Interrupted setup resumes from the client or completed earning already saved instead of creating duplicate ledger data.
- Existing synced ledgers skip first-run setup, and the decision waits for the initial cloud pull when the remote ledger is not yet known.
- Removed the old setup checklist from the empty ledger; first-time setup now has one onboarding flow, and the normal add button remains the entry point afterward.
- The supplied onboarding artwork is softened in Dark Mode.

### Project icons
- Project icon selection now shows the real ledger row before you save it, so the preview matches the component used in the ledger.
- Symbols are grouped into work, creative, digital, and commerce categories. A compact native control switches every project icon between **Outline** and **Fill**.
- Project icons now live in the regular Settings path. The selected symbol uses a quieter outlined state and a brief motion confirmation that respects Reduce Motion.

### Settings
- **Version** and **What’s new** now appear in the regular Settings path.
- **Import sample ledger** now imports an entirely fictional creative ledger instead of personal work data.

### Insights
- **Insights** now opens with one year-at-a-glance income chart: the total and covered dates sit above a smooth blue trend with its restrained diagonal band, a dotted divider, and month labels. The 3M / 6M / 1Y control now changes only that chart; the previous axis-heavy chart is removed.

## July 27, 2026

### Ledger reliability
- The **Earned in month** and **Stats** cards now update immediately after you delete or change an income line, import income, or receive synced changes.
- The **Earned in month** and **Stats** cards now follow the month at the top of the ledger while you scroll through history.
- Crossing a month boundary restores the summary's rolling month and amount, changing Stats figure, and smoothly reshaped six-month graph. Reduce Motion keeps these changes instant.

### Account access
- Removed **Sign in with Apple** from the iPhone app. Cloud access continues through Google or GitHub; local-only mode and device pairing are unchanged.

## July 26, 2026

### Project icons
- **Project icons** now uses a native filled-symbol palette, grouped by job, with a live `EntryRow` preview rather than a separate mock row. Assigned icons stay subtle beside their project name in the ledger, without adding default folder icons to every row.

### Getting started
- Signing in is back, and it is now the whole of the opening: Earnline starts on the account screen with **Continue with Apple**, Google, and GitHub, plus **Continue without an account** and **Pair a device** below. Choosing a local-only route no longer happens silently — it is your choice to make. Once you are in, you land on the ledger with nothing in the way.
- A three-screen illustrated introduction to the ledger's order — first a client, then the money they paid — now lives in **Settings › Experimental › Onboarding** rather than running by itself. Its last screen is real: name a client and pick their colour, the illustration fills in as you type, and finishing creates them and opens the income composer on them.
- **Project icons** has moved into Experimental alongside it.

### Simplified ledger
- Removed report and recap creation, previews, and sharing from Insights, client profiles, and the ledger.
- The Stats card is now a static monthly summary. Open **Insights** from the **…** menu when you want charts.
- Delete actions in contextual menus now show a matching red trash icon.

### First earnings
- The first-ledger header uses one calm month-and-total summary instead of empty Stats cards, and the bottom add control creates a client directly until one exists.

### Dev testing
- **earnline Dev** now has local account and onboarding previews for signed out, signing in, sign-in errors, offline errors, workspace setup, paired-device setup, and simulated sign out. These previews never contact a provider or Supabase, change a session, or modify ledger data.

## July 17, 2026

### Private sync security
- Workspace access is now enforced by authenticated Supabase membership for every ledger operation; the web sync service no longer bypasses row-level security.
- Pairing creates a device identity only after a valid ten-minute, one-use code is verified, avoiding unrestricted anonymous account creation.
- Workspace owners can now review paired devices in Settings and remove a lost or retired device; removal invalidates that device’s cloud access.
- Web sync batches concurrent reads and checks for remote updates less aggressively while still syncing local edits immediately, reducing free-plan function usage.

### Reliability
- If an older local ledger cannot be opened after an update, Earnline now keeps its files untouched instead of quitting. After you sign in, you can explicitly create a separate local cache for the authenticated workspace and import the older ledger later.
- If a previously signed-in iPhone starts while offline, it now opens the last server-verified local workspace instead of treating a transport outage as a sign-in failure. Server denials still stay blocked.
- Apple sign-in credentials are now rechecked when the app starts and when Apple revokes them, so a revoked Apple account returns this iPhone to the sign-in screen instead of keeping its old cloud session.
- Signing out now always removes this iPhone’s local session, even when it is offline; a paired device that could not be remotely disconnected is called out clearly so the owner can revoke it after reconnecting.
- Signed Release builds now require a configured HTTPS privacy-policy link, and show it in Settings under Privacy.
- Face ID now has the required system privacy explanation before it is used to unlock the ledger.
- App Lock now stays off when this iPhone has no device passcode, instead of looking protected while allowing an immediate unlock. Settings explains how to turn it on safely.
- If an Apple credential check cannot finish, Settings now explains the reduced protection and tells you how to restore it; explicit Apple revocation still blocks ledger access immediately.
- Before the first cloud sync, Earnline now stops and explains if it cannot safely remove local sample data; it never marks that cleanup complete or uploads around a failed cleanup.

### Onboarding
- The onboarding video now uses four distinct positions based on the live account-panel height: short panels leave the film full-screen, while medium, tall, and accessibility-height panels lift it progressively farther above the controls. A bare safe-area sound icon lets you enable or mute it without covering the film.
- The scripted ledger tour behind the account buttons has been replaced with the supplied looping onboarding video. Its sound is muted and the frame lifts dynamically above the account dock so the subject remains visible at normal and accessible text sizes.
- The account screen now uses one native 44-point control language: Apple remains system-owned, while Google, GitHub, local, pairing, recovery, and sign-out actions now share the same labelled full-width rhythm.
- Every account action now shares the Apple button’s visual label rhythm and native capsule geometry; Apple remains the single solid primary action while the alternatives use interactive Liquid Glass.
- **Earnline in Motion** now tells one connected income story rather than cycling through feature slides: a real draft line becomes paid, resolves into the monthly chart, and lands in its real client profile. The motion stays quiet and readable, while a calm settled ledger appears whenever motion should not play.
- The tour now uses one stable visual plane: directional native replacements take the place of competing camera transforms and matched-geometry movement, so story beats no longer jump, resize, or drift between states.
- The calmer 13-second tour now gives every moment time to read: the draft composer resolves into its saved row, the editor confirms its paid status, and the chart and client history enter with measured native motion.
- After you enter an empty ledger, one optional spotlight points to the first income action and disappears automatically after you save it.

### Search & developer builds
- Search filters now live in one native bottom-toolbar Filters menu. Date, Client, Project, and Status selections stay visible as system search tokens, and Clear filters returns to a clean search in one tap.
- The normal Debug build now installs a separate local-only earnline Dev companion with its own home-screen icon, so it can sit beside the production app without sharing its data or identity.
- Dev’s Debug menu once again renders every local auth-gate preview without enabling real authentication or sync.
- Supabase URL and publishable-key fields now live behind a dedicated **Personal Supabase database** screen with an explicit connection check and confirmation, instead of changing the active sync project while typing in Settings.

## July 15, 2026

### Onboarding
- The private-workspace entry is rebuilt as one calm, direct account screen: its spacious Earnline canvas makes the next step clear while Google, GitHub, and device pairing live together in native Liquid Glass controls.
- Sign-in, workspace checks, recoverable errors, and the handoff into the ledger now keep a stable hierarchy instead of jumping between welcome screens; finishing access fades directly into your ledger with no separate tour.
- Device pairing now explains the one-time QR scan in plain language, offers a solid manual-code fallback when the camera is unavailable, and lets the workspace owner generate a matching code from **Account & devices**.
- The account journey is fully available in English and Russian, with larger accessible controls, Dynamic Type support, and settings that respect Reduce Motion and Reduce Transparency.

## July 14, 2026

### Private account & device pairing
- Production now opens through a focused Google or GitHub sign-in gate; the existing Face ID/passcode app lock remains a separate privacy control, and Test remains local-only.
- First-run account setup is now a calm, two-step welcome and sign-in flow: it explains the private workspace before asking for a provider, gives pairing a clear secondary route, and keeps recovery states actionable.
- Local Debug builds now load their publishable Supabase configuration from an untracked file, so the account gate works without putting project values in source control.
- Owners can create a one-time, ten-minute QR code in **Account & devices** to pair another device. Pairing supports a camera scanner and an accessible manual-code fallback.
- Resolved accounts use separate local ledger containers, preventing a different account on the same device from reusing a previous account’s SwiftData cache.

### Insights & charts
- Income trends are redesigned as research-grade charts: a smooth line riding a diagonal-hatched band with an endpoint marker, each month's figure in a quiet row along the top, a large total and the covered period above, and no axis clutter; touch the chart to scrub — a value flag rides the dotted crosshair and the header shows that month's income and its change versus the month before.
- The global time-range toggle at the top of Insights is gone; the 3M / 6M / 1Y switch lives on the income chart itself, where it's the only card that needs one, and switching it no longer recomputes the whole sheet.
- The income calendar now covers a full year of days, and the section headings between cards are gone — each card speaks for itself.
- The income chart on client profiles uses the same standardized card, tinted with the client's color.

### Search filters
- Search now understands filters, not just text: while searching, minimal Date, Client, Project, and Status chips ride just above the search field, each opening a compact native menu built from your own ledger.
- Applied filters appear as native tokens in the search field and combine naturally — a client plus a month plus "Paid" narrows to exactly those lines, and two months means either month.
- Typing a date works too: "march", "march 2026", or "2026" finds lines from those dates, alongside the existing client, project, task, and amount matching.
- The results header keeps its running count and earned total for whatever combination of filters and text is active.
## July 20, 2026

### Ledger
- Scrolling across month boundaries is calmer on long histories: the ledger now uses the native list position instead of measuring every visible row, and summary graphs no longer morph while you scroll.
- Event notes now read as dated, full-width notes in the ledger; a month with only a note remains visible.

### Insights and sync
- The Stats card is now explicitly reachable to accessibility and automated checks, and Insights shows its loading state before preparing a large dashboard.
- Choosing the cloud copy now removes stale local project-icon preferences and month closures as well as income, clients, notes, and deletion records, so old local data cannot be pushed back to the workspace.

### Data
- Settings now includes CSV export and a safe import preview. CSV exchange is limited to income lines; invalid rows or duplicates stop the import before anything changes, and new clients require confirmation.

## July 13, 2026

### Search & bottom toolbar
- The ledger's bottom controls now match Apple's own list screens: a "…" circle, the system search field docked in the middle, and a "+" circle, all in the native Liquid Glass toolbar.
- Tapping the docked field expands the familiar system search experience, focused and ready to type; fixed the detached search bar that previously floated over the ledger.

### Client achievements
- Client profiles now include six automatic milestones derived from paid income history, with earned, locked, and progress states.
- Every achievement is a real procedural RealityKit 3D medal with metallic geometry and lighting; open one to rotate it directly, in the familiar Apple Fitness awards pattern.
- Client badges are now experimental, disabled by default, and controlled from the Experimental section in Developer Mode.

### Composer
- Restored the Smart Composer's original dimensions and control placement.

### Reliability
- Production and Test now keep separate currency profiles, local stores, and UI-test data; automated fixtures can no longer reach a real workspace.
- Removed leaked automated-test clients from Production and propagated their deletion to synced devices.
- App updates no longer reset the display conversion rate locally: configured workspaces read their authoritative currency profile from Supabase first.

### Settings
- Native menu pickers use the standard secondary-label gray while keeping the system popup, checkmark, and interaction behavior.

### Projects
- Every project already used in the ledger can now receive a familiar SF Symbol from Settings; the choice appears in project entry and client breakdowns and syncs through the shared workspace.

### Insights
- Monthly income now uses a smooth line with a soft area fill while keeping the familiar heatmap-first layout, summary figures, and client-share orb unchanged.

## July 12, 2026

### Native iOS polish
- Empty ledgers now use the system `ContentUnavailableView`, with a familiar primary action and built-in accessibility behavior.
- Haptic outcomes now use SwiftUI sensory feedback, and secondary interface text follows adaptive semantic label colors in every appearance.
- Developer Mode is remembered across Settings presentations and app launches.
- Added the remaining Russian catalog translations, including Stats, Month, Week, and Total.

### Reliability
- Release and Archive builds now use their own automatic signing configuration while unsigned simulator and CI builds remain isolated to Debug.
- The ledger's navigation, sheets, confirmations, composer, rows, headings, summary header, and bottom controls now use typed routes and focused SwiftUI views instead of one oversized screen state.
- Bottom actions now live in a native SwiftUI safe-area bar, isolating them from the UIKit toolbar hierarchy used by the hosting controller.

### Performance
- Client profiles now open immediately even with years of transactions: history totals and breakdowns are prepared once in the background instead of repeatedly scanning the ledger during navigation.
- Status, project, and transaction drill-downs fetch only the selected client's rows when opened, keeping the compact profile lightweight.

## July 11, 2026

### Insights
- Insights opens immediately on large ledgers by preparing its dashboard totals once outside the render path and lazily building lower sections.
- The monthly chart now shows actual income totals, with exact selection details and a secondary comparison to the previous month.
- The client-share orb is crisper and calmer, sits above a full-width ranked client list, and no longer relies on a heavy blurred glow.
- Top clients now restores the share-shaped color orb with a finer, better-separated outer ring and a redesigned ranked list with aligned income, percentages, and proportional tracks.
- The earnings heatmap now has a smooth blue day-selection ring, a quieter reveal, Reduce Motion support, and one accessible adjustable calendar surface.

### Client profile
- The client page now matches the new compact profile: a client-color name chip, total/average/share figures, and a scrubbable 12-month line chart.
- Statuses, projects, and all transactions are concise summary rows that open focused transaction lists instead of stretching the profile into a second ledger.
- Renaming, recoloring, and deleting a client moved behind an Edit button into their own sheet — changes apply when you confirm, and Cancel really cancels.

### Ledger
- The ledger now loads progressively: launch reads only the most recent months, and older months materialize seamlessly as you scroll back — so opening the app stays instant no matter how many years of lines it holds. Search still spans the full history.
- The app launches noticeably faster on large ledgers: the ledger's totals are computed once and reused, instead of being recomputed from every line each time the screen redraws during startup.
- Scrolling and editing stay smooth on ledgers with thousands of lines: the list and its summary cards now aggregate months, totals, and trends in a single pass instead of re-scanning every line for every month.
- Removed the detached lower scroll fade so the ledger now meets the native Liquid Glass controls with a clean edge.
- The summary cards now react with native interactive Liquid Glass.

### Amounts
- Amounts across the app, including compact chart labels, now display as correctly rounded whole values without decimal digits; stored and synced values keep their original precision.
- The selected currency pair and exchange rate now sync through the shared Supabase workspace profile.

### Settings
- Typing a conversion rate no longer makes the app stutter: the value now applies once you finish editing the field instead of re-converting every displayed amount on each keystroke.
- Developer tools are grouped into Supabase, Sync, Data, and About sections again.

### Composer
- The Add line button now uses a native interactive Liquid Glass treatment without enlarging the compact composer.

## July 10, 2026

### Ledger
- The Add (+) and More (…) controls are balanced standard Liquid Glass buttons with clearer icons and consistent bottom-edge spacing.

### Settings
- Currency pickers no longer use decorative leading icons.
- Developer Mode reveals its advanced controls in a separate section below the toggle.

## July 9, 2026

### Insights
- The daily earnings heatmap now starts each week on Monday.

### Localization
- The app now ships in English and Russian.

### Smaller improvements
- The client color picker's selection ring now animates the same way on the New client and client detail screens.

### Search
- Search is the system iOS 26 Liquid Glass field in the bottom toolbar (same pattern as Mail). Tap the magnifying glass to expand it; Cancel dismisses.
- Add (+) and More (…) sit in that same toolbar. Matching lines filter the ledger in place; the top summary stays in a compact form while you search.

## July 8, 2026

### Settings
- Settings is now a native iOS form — system row heights, separators, and section footers.
- New Appearance setting: System / Light / Dark (previously only a dark-mode toggle). "System" follows your device.
- Row icons are monochrome ink instead of the accent color; decorative icons removed from the Appearance rows.
- The app-lock toggle is labeled honestly per device: Face ID, Touch ID, Optic ID, or Passcode.
- Added this "What's new" screen.

### Search
- Search moved behind the "…" menu — the field appears only when you ask for it and leaves the ledger clean otherwise.
- Search now uses the native iOS search field, with an "Earned total" summary above the results.

### Formatting
- Dates, decimal separators, and heatmap weekday letters now follow your device region and language instead of being hardcoded.

### Privacy & reliability
- The privacy cover now appears the moment the app becomes inactive (app switcher, incoming call) — amounts no longer flash in the multitasking view. Returning without backgrounding doesn't re-ask for Face ID.
- The app lock can no longer strand you on the lock screen if the device passcode was removed.
- Removing a client stages its Undo only after the delete actually saved; a failed Undo restore now shows an error instead of pretending it worked.

### Sync
- Fixed a race where switching workspaces mid-sync could write sync state into the wrong workspace.
- Malformed server rows are skipped instead of being silently re-dated to "now"/"today" — protects entry dates and conflict resolution.
- Calendar days sync timezone-safely between iOS and the web app; traveling across timezones no longer shifts entry dates.
- Legacy demo-data cleanup can no longer delete real entries that merely look like the old samples.

### Entry parsing
- Amounts with text currency codes are recognized: "500 usd", "24k eur".
- Status words work alongside emoji: "pending", "paid", "done", "cancelled" (and Russian equivalents) at the start or end of a line.
- An amount buried mid-sentence is no longer mistaken for the line's amount, and zero-amount lines can't be committed.

### Smaller improvements
- Pull-to-refresh on the ledger triggers a sync.
- Deleting a heading now asks for confirmation, like entries and clients.
- Insights period picker labels corrected to 3M / 6M / Y.
- Small controls (status dot, composer submit, chart's clear button) meet the 44-point tap-target guideline.
- Reduce Motion is respected across the app's animations.
