# earn›line for iPhone

**The primary Earnline experience.** This native SwiftUI app is a calm place
to capture independent work, understand the month, and keep a personal ledger
close at hand.

[Back to the project overview](../README.md) · [Run locally](#run-locally) · [Optional web companion](../web/README.md)

## A small screen tour

<table>
  <tr>
    <td align="center" width="33.33%">
      <img src="../docs/screenshots/readme/ios-ledger.png" alt="Earnline iPhone ledger with fictional sample data" width="220" />
      <br /><sub><b>Ledger</b><br />A readable month, not a dashboard.</sub>
    </td>
    <td align="center" width="33.33%">
      <img src="../docs/screenshots/readme/ios-composer.png" alt="Earnline iPhone income composer with fictional sample data" width="220" />
      <br /><sub><b>Composer</b><br />Add a line without breaking focus.</sub>
    </td>
    <td align="center" width="33.33%">
      <img src="../docs/screenshots/readme/ios-filters.png" alt="Earnline iPhone search with native Filters control" width="220" />
      <br /><sub><b>Search</b><br />Find work with words and native filter tokens.</sub>
    </td>
  </tr>
</table>

## What the iPhone app is for

- Capture income with amount, client, project, task, date, and payment state in
  one focused composer.
- See the important hierarchy at a glance: amount first, work second, and
  dates and status as quieter context.
- Keep working offline. The ledger lives in SwiftData on the device first.
- Search text, then refine it with the bottom `Filters` menu for Date, Client,
  Project, and Status. Selected choices remain visible as search tokens.
- Use the app fully locally, or sign in to a private workspace and pair your
  own devices when sync is useful.

## Run locally

```bash
cd ios-app
xcodegen generate
open earnline.xcodeproj
```

Select the `earnline` scheme and run it on an iPhone simulator or a connected
iPhone. `project.yml` is the Xcode project source of truth, so regenerate after
adding files or changing build settings.

For a regression check, use Xcode's Test action or run the scheme's tests:

```bash
xcodebuild \
  -project earnline.xcodeproj \
  -scheme earnline \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  test
```

## Development companion

For local Debug runs, Xcode can also install the separate `earnline Dev`
companion on the same destination. It has its own blue Dev icon and bundle
identifier (`com.earnline.app.dev`) and stays local-only; it is not a
production-sync app.

The production app keeps `com.earnline.app` and the standard app icon. See
[`project.yml`](project.yml) for the target configuration and
[`../docs/README.md`](../docs/README.md) for private sync operations.
