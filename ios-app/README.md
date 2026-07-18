# earn›line for iPhone

The native SwiftUI companion for keeping an income ledger. It is designed for
quick entry, clear month totals, and a calm phone-native workflow.

![The iOS ledger with fictional local sample data](../docs/screenshots/readme/ios-ledger.png)

## What it does

- Add income with a focused composer: amount, client, project, task, date, and
  payment state.
- Keep the ledger locally on the device, including when the network is absent.
- Search text and refine it with the native bottom `Filters` menu for Date,
  Client, Project, and Status. Selected choices remain searchable tokens.
- Connect a private workspace when needed to synchronize with the web app and
  a paired device.

| Native filters | Composer |
| --- | --- |
| ![Search with the native Filters control](../docs/screenshots/readme/ios-filters.png) | ![The income composer](../docs/screenshots/readme/ios-composer.png) |

![Settings on a local device](../docs/screenshots/readme/ios-local-only.png)

## Run locally

```bash
cd ios-app
xcodegen generate
open earnline.xcodeproj
```

Run the `earnline` scheme on an iPhone simulator or a connected iPhone.
For local Debug runs, Xcode also installs the separate `earnline Dev` companion
to that same destination. It has its own blue Dev icon and bundle identifier
(`com.earnline.app.dev`), and stays local-only; it is not a production-sync app.

The production app keeps `com.earnline.app` and the standard app icon. The
project file is generated from `project.yml`.
