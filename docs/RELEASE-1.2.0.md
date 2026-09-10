# Earnline iOS 1.2.0 (5)

Scope: iOS audit fixes and an unsigned IPA for the owner's existing installation workflow.
Currency conversion remains live: changing the display rate reprices all
history. No historical rate, money rounding, earned-status, or global currency
toggle changes are included.

## Implemented

- [x] Preserve and commit the September 5 fixes (2934de5c, local v1.1.1 tag).
- [x] Safety snapshots and merge-only restore; preview new/existing backup rows.
- [x] Fix summary hit testing and the unbounded accessibility spacer.
- [x] Direct income form preserves the selected month, currency, and client; closing a nonempty draft requires an explicit choice.
- [x] External Home Screen/Spotlight navigation waits while a form, inline composer, or another flow is open.
- [x] Shared AppModel and SwiftData container for App Intents, foreground use, and background refresh.
- [x] Reminder writes are serialized; workspace changes clear pending and delivered notifications; app lock suppresses details.
- [x] Adaptive summary, auth, rows, client chips, month dividers, and profile metrics; 57 new Russian catalog entries.
- [x] Imports enforce an actual 20 MB read limit; search is debounced by 180 ms and reuses its loaded rows.
- [x] Combined sync reads use bounded 250-row pages per table, precise cursors, and a missing-function-only compatibility fallback.
- [x] Widget, Control Center add action, text Share extension, and optional Spotlight indexing.
- [x] Expired-session refresh failures restore only the same user's previously verified workspace on a network error.
- [x] Atomic SQL tests and combined-read isolation tests are wired into CI and passed locally on PostgreSQL 17.
- [x] Bundled video reduced from 15,314,954 to 2,502,863 bytes; 1080 × 1920, duration, and audio retained. Original preserved under ignored build/source-media/.

## Verification

All evidence below is local and ignored by Git, under build/verification/1.2.0/.

- Xcode 27.0 (27A5228h), iPhone 17 simulator with iOS 27.0. Deployment target remains iOS 26.
- The final Everyday result reports 301 passed test executions and 0 failures. The log also reports 261 tests in 31 suites; the difference is dynamic-parameter and UI execution accounting in Xcode 27.
- Expired authentication: five scenarios passed using the actual Supabase session refresh path and a mock transport. Offline access succeeds only with the matching cached membership; revoked session, missing membership, different user, and missing session fail closed.
- Draft test exercises Keep editing, save to the selected client, explicit discard, and a fresh empty form. Passed in draft-alert.xcresult.
- Home Screen Search action preserves an open income draft and executes after its dismissal. Passed in final-fixes.xcresult.
- Russian dark form with keyboard and safety-snapshot route passed semantic UI checks. Maximum-size Russian composer and summary interaction were covered in the full UI runs.
- Actual Release build and three Release UI tests passed in release-final.xcresult on a new isolated simulator. Release ignores Debug automation arguments, offers GitHub entry without developer configuration, and retains an entry point at the largest text size.
- Simulator inspection returned a nonempty accessibility tree (207 elements) plus PNG. Screenshot attachments are retained under ignored .ios-simulator-output/release-1.2/; the final agent runtime could not accept image inputs, so these captures are not claimed as a complete visual review.
- SwiftLint with strict mode, git diff --check, and nine Release configuration guard cases passed.
- Local SQL suite passed: concurrent writes, stale-batch rollback, explicit restore, caller isolation, and combined-read paging. The read-only RPC was deployed first to test, then production; permission checks passed and production record counts/digests were unchanged.
- Russian App Shortcuts strings and language metadata are present in the Release app.
- Final artifact: `build/releases/earnline-1.2.0-5-v2/earnline-1.2.0-5-unsigned.ipa`; SHA-256: `2ecdd7f446660a4cf0b2e7987883150570050824632ef8dd5c739f150c0f080c2`.

## Verification Boundaries

- The IPA is deliberately unsigned. Re-signing must preserve the OAuth URL scheme and support group.com.earnline.app for the widget and Share extension.
- Physical installation, update over existing iPhone data, real OAuth, Siri speech recognition, VoiceOver gestures, and two-device end-to-end sync remain unverified for this build. Simulator test fixtures do not use the owner's ledger.
- Widget and Share targets compile and embed successfully; end-to-end widget display, Share invocation, and app-group behavior after re-signing remain device checks.
- Background refresh currently uses an already prepared signed-in runtime; cold background authentication and guaranteed refresh cadence are not implemented. App Intents require the selected workspace to be ready; locked client queries do not expose names.
- Safety restore adds missing rows. It cannot overwrite an existing conflicting cloud row or undo a cloud replacement in full.
- Server delete-versus-update semantics and full tombstone replay are retained. No age-based tombstone deletion was introduced. Complete tombstone cursors/compaction and moving all merge work off the main actor remain future work.
- Public App Store submission and Sign in with Apple configuration are outside this unsigned distribution. No App Store readiness claim is made.
- No push or publication is included; there is no remote CI result for the final local commit.
