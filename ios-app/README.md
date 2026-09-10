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

## Current release

[Earnline 1.2.1 (7)](https://github.com/Piwqust/earnline/releases/tag/v1.2.1)
provides unsigned primary and Dev IPAs with SHA-256 checksums. The primary app
includes widget and Share extensions; Dev remains a separate local-only app.
Read the [release notes](../docs/RELEASE-1.2.1.md) before re-signing or updating.

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
earnline_xcode_developer_dir="/path/to/Xcode-beta.app/Contents/Developer"
DEVELOPER_DIR="$earnline_xcode_developer_dir" xcodebuild \
  -project earnline.xcodeproj \
  -scheme earnline \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  test
```

### Test plans

`Everyday` is the default plan for feature and visual work. It excludes the
rare large-text accessibility UI check, so a normal `xcodebuild test` or Xcode
**Product → Test** does not run it.

Before an App Store or release-readiness pass, select **Product → Test Plan →
AppStoreRelease** in Xcode, or add `-testPlan AppStoreRelease` to the command
above. That plan includes the accessibility check as well as the normal tests.

## Xcode 27 beta and MCP

Xcode 27 and its native Xcode MCP server are the standard local toolchain for
agent-assisted Earnline work. The server follows the project, scheme, and run
destination selected in the open Xcode window. For Earnline, open
`earnline.xcodeproj`, select the `earnline` scheme, and use an iPhone 17
simulator on the iOS 27 runtime. This verifies iOS 27 behavior; it does not
raise the app's iOS 26 deployment target.

In Xcode, enable `Xcode → Settings → Intelligence → Model Context Protocol →
Allow external agents to use Xcode tools`. For Codex, verify the workstation
bridge before a session:

```bash
codex mcp get xcode
```

If the `xcode` server is absent, add the native bridge once:

```bash
codex mcp add xcode -- xcrun mcpbridge
```

Before a verification pass:

1. List Xcode windows and keep the returned tab identifier.
2. Confirm the active scheme and switch the run destination explicitly.
3. Get the test list before constructing targeted test identifiers.
4. Run the focused tests first, then the complete active test plan.
5. Check Xcode's Issue navigator separately; a passing build does not prove
   that the UI interaction or the complete test plan passed.

Xcode's GUI and terminal can point at different installations. Verify the
command-line toolchain before using CLI results as iOS 27 evidence:

```bash
earnline_xcode_developer_dir="/path/to/Xcode-beta.app/Contents/Developer"
DEVELOPER_DIR="$earnline_xcode_developer_dir" xcodebuild -version
DEVELOPER_DIR="$earnline_xcode_developer_dir" \
  xcrun --sdk iphonesimulator --show-sdk-version
```

Prefer setting `DEVELOPER_DIR` per command over changing the machine-wide
`xcode-select` setting. If a standalone Simulator MCP reports an IDB companion
disconnect on a new beta runtime, treat that as a tool-compatibility failure,
not an app failure. Use the native Xcode MCP test actions or XCUITest for taps
and accessibility assertions; standalone simulator screenshots remain useful
for optical inspection.

## Development companion

For local Debug runs, Xcode can also install the separate `earnline Dev`
companion on the same destination. It has its own blue Dev icon and bundle
identifier (`com.earnline.app.dev`) and stays local-only; it is not a
production-sync app.

The production app keeps `com.earnline.app` and the standard app icon. See
[`project.yml`](project.yml) for the target configuration and
[`../docs/README.md`](../docs/README.md) for private sync operations.
