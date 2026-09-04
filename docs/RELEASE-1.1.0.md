# Earnline 1.1.0

Released September 4, 2026.

Earnline 1.1.0 is a stable GitHub update aimed at local-first daily use. It is
not an App Store distribution: the attached IPA files are unsigned
review artifacts and must be re-signed or built from source before installation.
Optional Supabase synchronization remains a separately configured beta feature.

## Highlights

- Added safe, merge-only JSON backup and restore for the complete local ledger,
  including settings, notes, project icons, and month reviews.
- Made money parsing consistent across regional settings and rounded saved
  amounts to the precision used by the sync contract.
- Hardened sync conflict handling, pending-change reporting, import rollback,
  project-icon merges, and exchange-rate requests.
- Improved large-ledger loading and aggregation without blocking the visible
  client profile or recalculating the complete ledger during routine renders.
- Restored reliable access to Insights from the Stats summary card.
- Added Russian camera and Face ID permission text and completed the new backup
  interface translations.
- Removed 19 React hook and compiler warnings from the optional web companion,
  including stale memo dependencies and synchronous effect-driven rerenders.
- Fixed the Dev companion packaging so it no longer embeds a second copy of the
  primary app bundle.
- Updated Supabase Swift to 2.55.1.

## Assets

- `earnline-1.1.0-unsigned.ipa` — primary app, Release configuration.
- `earnline-dev-1.1.0-unsigned.ipa` — separate local-only development companion.
- `SHA256SUMS.txt` — SHA-256 checksums for both archives.

## Installation boundary

The IPA files are unsigned. They cannot be installed directly by tapping them
on an iPhone. The supported path is to clone the repository, generate the Xcode
project, select your Apple development team, and run the `earnline` scheme on a
connected iPhone.

## Known limits

- Signed archive, install, and launch were not verified on a physical iPhone for
  this GitHub release.
- The public artifacts contain no production Supabase endpoint. Cloud sync,
  OAuth, row-level security, and multi-device behavior require the operator's
  own configured deployment and separate end-to-end verification.
- Existing foreign-currency lines are displayed using the current configured
  conversion rate; Earnline does not preserve the historical rate per entry.
- This release has not been submitted to App Store review.
