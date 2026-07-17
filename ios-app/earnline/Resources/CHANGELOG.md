# What's new

## July 17, 2026

### Private sync security
- Workspace access is now enforced by authenticated Supabase membership for every ledger operation; the web sync service no longer bypasses row-level security.
- Pairing creates a device identity only after a valid ten-minute, one-use code is verified, avoiding unrestricted anonymous account creation.
- Workspace owners can now review paired devices in Settings and remove a lost or retired device; removal invalidates that device’s cloud access.
- Web sync batches concurrent reads and checks for remote updates less aggressively while still syncing local edits immediately, reducing free-plan function usage.

### Onboarding
- The account screen now uses one native 44-point control language: Apple remains system-owned, while Google, GitHub, local, pairing, recovery, and sign-out actions now share the same labelled full-width rhythm.
- Every account action now shares the Apple button’s 17-point semibold label rhythm and native capsule geometry; Apple remains the single solid primary action while the alternatives use interactive Liquid Glass.
- **Earnline in Motion** now tells one connected income story rather than cycling through feature slides: a real draft line becomes paid, resolves into the monthly chart, and lands in its real client profile. The motion stays quiet and readable, while a calm settled ledger appears whenever motion should not play.
- The tour now uses one stable visual plane: directional native replacements take the place of competing camera transforms and matched-geometry movement, so story beats no longer jump, resize, or drift between states.
- The calmer 13-second tour now gives every moment time to read: the draft composer resolves into its saved row, the editor confirms its paid status, and the chart and client history enter with measured native motion.
- After you enter an empty ledger, one optional spotlight points to the first income action and disappears automatically after you save it.

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
