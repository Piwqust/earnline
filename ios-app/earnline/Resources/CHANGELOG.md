# What's new

## July 13, 2026

### Search
- Search now lives in the ledger's "…" menu and opens the system search experience focused and ready to type.
- Fixed the resting search bar that floated over the bottom of the ledger.

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
