# Earnline agent guide

## Read first

- Read `PRODUCT.md` before product, UX, data-model, or navigation work.
- Read `DESIGN.md` before any visual or interaction change.
- Treat this repository as one iPhone-first product: native SwiftUI in `ios-app/` is the primary client, while the desktop-first React app in `web/` is an optional companion.
- Preserve the personal product model: one shared Supabase workspace, no login, no password, and no account UI unless the user explicitly changes that requirement.

## Xcode 27 and MCP baseline

- Use Xcode 27 and its native Xcode MCP server as the default local toolchain for agent-assisted iOS work. This is a development and iOS 27 verification baseline; it does not change Earnline's iOS 26 deployment target unless `ios-app/project.yml` is explicitly changed.
- Open `ios-app/earnline.xcodeproj` in Xcode 27 and enable `Xcode → Settings → Intelligence → Model Context Protocol → Allow external agents to use Xcode tools`. Connect Codex through `xcrun mcpbridge`; the native server follows the open Xcode window rather than a project path supplied in a terminal command.
- Before an iOS action, identify the Xcode window, confirm the active scheme and run destination, and switch them deliberately. Default to `earnline` on iPhone 17 with the iOS 27 runtime. Use `earnline-dev` only for Debug-only checks and `earnline-device` only for an explicitly physical-device task.
- Prefer the native Xcode MCP server for build, run, tests, simulator input, screenshots, accessibility hierarchy, logs, and Xcode configuration. Keep XCUITest for durable regression coverage. A standalone Simulator MCP or IDB companion disconnect on a beta runtime is a tool-compatibility failure, not proof of an app failure.
- Treat Xcode 26/iOS 26 and Xcode 27/iOS 27 evidence as separate. When using the command line, set `DEVELOPER_DIR` per command to the Xcode 27 installation and verify it with `xcodebuild -version`; never change machine-wide `xcode-select` for this repository.

## Design workflow

For every user-visible change, inspect the running surface before editing and verify the running surface after editing. A successful compile is not visual verification.

### Broad redesigns and new flows

1. State the user, job, entry point, happy path, failure path, and completion state.
2. Read `PRODUCT.md` and `DESIGN.md`, then inspect the relevant implementation and current screenshots.
3. Find 3–5 focused references in Mobbin or an approved Figma file. Explain which interaction or hierarchy each reference contributes; do not copy an entire aesthetic wholesale.
4. Present one coherent direction before implementation. Resolve navigation, hierarchy, density, states, and accessibility before decorative styling.
5. Implement a complete vertical slice, then run it and compare before/after screenshots at the same viewport or simulator.

Small, well-scoped fixes do not require a separate design proposal, but they still require runtime verification.

### Required skill routing

- iOS visual and interaction work: use `ios-hig-design`, `mobile-ios-design`, and `swiftui-ui-patterns`.
- iOS 26 glass work: also use `swiftui-liquid-glass`.
- iOS runtime checks: use the native Xcode 27 MCP server (`xcrun mcpbridge`) and inspect screenshots plus the accessibility hierarchy.
- Web visual work: use `impeccable`; use browser automation for live inspection, keyboard checks, console errors, responsive states, and screenshots.
- Figma is a source of truth only when the user supplies or approves a file or node. Do not invent a parallel Figma system that drifts from code.

### Design acceptance checklist

- The primary action is obvious and frequent actions are immediately reachable.
- Advanced and developer controls stay out of the normal path.
- Utility icons use one coherent monochrome language and have clear labels or accessibility names.
- Touch targets are at least 44×44 pt on iOS; web controls remain keyboard reachable with a visible focus state.
- Verify light and dark appearance, Dynamic Type or text zoom, VoiceOver or semantic labels, Reduce Motion, empty, loading, error, offline, and long-content states as applicable.
- Motion communicates state and respects Reduce Motion; it is never decorative choreography.
- No content is clipped at compact widths, large accessibility sizes, or long localized strings.

## Visual rules

- Content comes first. Liquid Glass is reserved for navigation, toolbars, menus, transient controls, and other functional chrome. Do not use glass as a decorative content-card material.
- Prefer native SwiftUI controls and familiar iOS placement over custom affordances. On the web, use web-native navigation and controls rather than porting the phone layout.
- Use the blue accent for primary action, focus, and selection. Client colors identify clients; status colors communicate status. Do not spread saturated color onto inactive chrome.
- Avoid generic colored settings glyphs, dense developer dashboards, tiny floating controls, unexplained toolbar actions, repeated metric-card grids, nested cards, and decorative glassmorphism.
- Keep ledger rows highly scannable: amount first, work description second, date and secondary metadata quieter, status perceivable without relying on color alone.

## iOS implementation

- `ios-app/project.yml` is the Xcode project source of truth. Run `xcodegen generate` after adding files or changing build settings.
- Prefer small SwiftUI views with narrow state ownership. Do not add more unrelated state or business logic to oversized screens; extract focused subviews or models when the change naturally creates a boundary.
- Use `@State`, `@Binding`, `@Observable`, and typed environment dependencies according to ownership. Avoid multiple booleans for mutually exclusive sheets and routes.
- Preserve swipe actions, first-tap search focus, currency tap toggles, keyboard behavior, and existing accessibility semantics during layout refactors.
- Do not swallow save or sync failures with `try?`. Keep the UI calm, but surface failure and preserve user data.
- User-visible iOS changes require an entry in `ios-app/earnline/Resources/CHANGELOG.md` under the current date. Internal refactors and test-only changes do not.

### iOS verification

- Prefer the native Xcode 27 MCP server for build, run, simulator interaction, screenshots, logs, UI inspection, and active-project configuration.
- Build and run the explicitly selected scheme; normally this is `earnline` on the booted iPhone 17 iOS 27 simulator.
- Run relevant unit tests; run the full iOS test suite for shared model, sync, parser, or navigation changes.
- The default `Everyday` test plan skips release-only accessibility-size UI checks. Select `AppStoreRelease` only when the user explicitly asks for an App Store or release-readiness pass; do not turn it on for routine feature or visual work.
- Capture the changed screen and exercise the actual interaction, not only its launch state.
- Review the Xcode Issue navigator separately. A successful build, launch, or screenshot does not prove that the interaction and full test plan passed.

## Optional web companion

- Keep the web client desktop-first with its own sidebar, ledger, and summary-rail composition. It supports the iPhone-first product rather than setting a parallel feature direction. Share product semantics and tokens with iOS, not platform-inappropriate layouts.
- Reuse components and tokens under `web/src/ui/components/` and `web/src/ui/theme/`; do not introduce one-off colors, radii, shadows, or control vocabularies.
- Preserve semantic HTML, keyboard navigation, focus restoration, responsive behavior, and Realtime/offline states.

### Web verification

- From `web/`, run `npm test`, `npm run typecheck`, and `npm run build` for affected code.
- Inspect at a desktop viewport and at least one narrow viewport. Check keyboard navigation, focus visibility, console errors, loading, empty, and error states.
- Capture before/after screenshots for visual changes at identical viewport sizes.

## Data, sync, and repository safety

- SwiftData and IndexedDB are the local sources of truth; Supabase synchronization is last-write-wins with tombstones. Keep wire formats aligned across both clients.
- Keep money precision-safe and maintain matching status/schema mappings across Swift, TypeScript, and SQL.
- Never commit real Supabase URLs, keys, workspace identifiers, client names, income data, device identifiers, or screenshots containing private ledger data.
- Preserve unrelated user changes. The worktree may already be dirty; inspect `git status` before editing and never discard changes you did not create.

## Completion standard

Report what changed, what was verified, and any remaining uncertainty. Do not claim a UI task is complete without a runtime check on the affected platform.
