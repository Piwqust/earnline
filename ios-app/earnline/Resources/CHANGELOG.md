# What's new

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
