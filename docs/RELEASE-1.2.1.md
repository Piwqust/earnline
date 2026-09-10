# Earnline iOS 1.2.1 (7)

This release collects the September reliability and iPhone integration changes
since 1.1.0, restores the original ledger flow, and corrects the Stats card style.
Requires iOS 26 or later. Built with Xcode 27.

## Changes

- The original two-card header and inline income composer are restored. Stats
  uses the same neutral heading, typography, padding, and glass shape as the
  earnings card, while retaining its graph and Insights action.
- Opening the inline composer scrolls to the selected client and month.
- Safety snapshots are created before local reset or cloud-copy replacement.
  Restore adds missing rows without overwriting existing ones; backup imports
  preview new and existing records before confirmation.
- An expired session can reopen the same previously verified workspace when
  the network is unavailable. Revoked access still requires signing in.
- Money input, currency changes, import limits, notification privacy, and
  synchronization error handling are hardened. Search is debounced, and sync
  reads use bounded pages.
- Home Screen actions, App Shortcuts, optional Spotlight indexing, a widget,
  a Control Center add action, and a text Share extension are included.
- The welcome video is smaller, and Russian strings and large-text layouts
  have been improved.

Currency conversion remains live: changing the display rate recalculates
historical displays. Original amounts and currencies remain authoritative.

## Downloads

- `earnline-1.2.1-7-unsigned.ipa`: primary app, `com.earnline.app`, with widget
  and Share extensions.
- `earnline-dev-1.2.1-7-unsigned.ipa`: separate local-only Dev companion,
  `com.earnline.app.dev`.
- `SHA256SUMS.txt`: SHA-256 checksums for both IPAs.

These are deliberately unsigned archives. Install through a compatible signing
workflow or build from Xcode with your own team. Preserve the OAuth URL scheme
and `group.com.earnline.app` entitlement for the primary app and extensions.
Before updating an existing installation, export a ledger backup from Settings.
Do not delete the existing app to update it.

## Verification

- The Stats change passed an Xcode 27 simulator build and the focused
  `testStatsCardOpensInsights` UI test. Light and dark screenshots and nonempty
  accessibility hierarchies were inspected on iPhone 17 / iOS 27.
- The earlier local 1.2.1 audit recorded 299 passing Everyday tests and a passing
  Release UI action. Those results predate the final Stats styling change.
- Current automated checks are recorded in
  [GitHub Actions](https://github.com/Piwqust/earnline/actions/workflows/ci.yml).
  The release description records the final publication checks and artifact hashes.

## Boundaries

- Physical iPhone installation, updating over existing data, real OAuth,
  VoiceOver gestures, Siri speech, and two-device sync have not been verified
  for these unsigned artifacts.
- Widget, Share extension, and App Group behavior after re-signing require
  device verification. Background refresh needs a prepared signed-in runtime;
  its timing is controlled by iOS.
- Safety restore adds missing rows; it does not overwrite conflicting rows or
  fully undo a cloud replacement.
- No App Store readiness claim is made. This release does not change production
  infrastructure or apply database migrations.
