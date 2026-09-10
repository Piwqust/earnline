# Earnline iOS 1.2.1 (6)

Scope: iOS audit fixes and an unsigned IPA for the owner's existing installation workflow.
Currency conversion remains live: changing the display rate reprices all
history. No historical rate, money rounding, earned-status, or global currency
toggle changes are included.

## Implemented

- [x] Preserve and commit the September 5 fixes (2934de5c, local v1.1.1 tag).
- [x] Safety snapshots and merge-only restore; preview new/existing backup rows.
- [x] Fix summary hit testing and the unbounded accessibility spacer.
- [x] Restored the original two-card ledger header: monthly earnings on the left and tappable statistics with the trend graph on the right.
- [x] Restored the original inline income composer and added automatic scrolling to the selected client/month when it opens.
- [x] External Home Screen/Spotlight navigation remains available alongside the inline composer.
- [x] Shared AppModel and SwiftData container for App Intents, foreground use, and background refresh.
- [x] Reminder writes are serialized; workspace changes clear pending and delivered notifications; app lock suppresses details.
- [x] Technical accessibility and reliability fixes remain in place; the original ledger header, row styling, auth surface, and client profile layout are restored.
- [x] Imports enforce an actual 20 MB read limit; search is debounced by 180 ms and reuses its loaded rows.
- [x] Combined sync reads use bounded 250-row pages per table, precise cursors, and a missing-function-only compatibility fallback.
- [x] Widget, Control Center add action, text Share extension, and optional Spotlight indexing.
- [x] Expired-session refresh failures restore only the same user's previously verified workspace on a network error.
- [x] Atomic SQL tests and combined-read isolation tests are wired into CI and passed locally on PostgreSQL 17.
- [x] Bundled video reduced from 15,314,954 to 2,502,863 bytes; 1080 × 1920, duration, and audio retained. Original preserved under ignored build/source-media/.

## Verification

All evidence below is local and ignored by Git, under build/verification/1.2.1/.

- Xcode 27.0 (27A5228h), iPhone 17 simulator with iOS 27.0. Deployment target remains iOS 26.
- The final Everyday result completed with exit code 0: 299 tests passed and 0 failed. The unit portion reports 261 tests in 31 suites, and the UI stress scenario passed.
- Expired authentication: five scenarios passed using the actual Supabase session refresh path and a mock transport. Offline access succeeds only with the matching cached membership; revoked session, missing membership, different user, and missing session fail closed.
- The original inline composer accessibility and summary-card interactions passed, including the real + -> Income -> client add-income path and the Russian largest-text layout check.
- The Release UI action completed with exit code 0 on the production scheme.
- Final unsigned IPA: build/releases/earnline-1.2.1-6/earnline-1.2.1-6-unsigned-final.ipa.
- Final IPA SHA-256: 4329052e43522732903499a4524c18b85ed3abaebaea364f4b1754c33c1de585.
- Simulator inspection returned a nonempty accessibility tree with 256 elements, including both summary-card identifiers and the restored inline composer entry points. The screenshot was captured at 368 x 800 px; visual image review was unavailable in this runtime.
- SwiftLint with strict mode and git diff --check passed after the final source changes.
- Local SQL suite passed: concurrent writes, stale-batch rollback, explicit restore, caller isolation, and combined-read paging. The read-only RPC was deployed first to test, then production; permission checks passed and production record counts/digests were unchanged.
- Russian App Shortcuts strings and language metadata are present in the Release app.

## Verification Boundaries

- The IPA is deliberately unsigned. Re-signing must preserve the OAuth URL scheme and support group.com.earnline.app for the widget and Share extension.
- Physical installation, update over existing iPhone data, real OAuth, Siri speech recognition, VoiceOver gestures, and two-device end-to-end sync remain unverified for this build. Simulator test fixtures do not use the owner's ledger.
- Widget and Share targets compile and embed successfully; end-to-end widget display, Share invocation, and app-group behavior after re-signing remain device checks.
- Background refresh currently uses an already prepared signed-in runtime; cold background authentication and guaranteed refresh cadence are not implemented. App Intents require the selected workspace to be ready; locked client queries do not expose names.
- Safety restore adds missing rows. It cannot overwrite an existing conflicting cloud row or undo a cloud replacement in full.
- Server delete-versus-update semantics and full tombstone replay are retained. No age-based tombstone deletion was introduced. Complete tombstone cursors/compaction and moving all merge work off the main actor remain future work.
- Public App Store submission and Sign in with Apple configuration are outside this unsigned distribution. No App Store readiness claim is made.
- No push or publication is included; there is no remote CI result for the final local commit.
