# Earnline privacy

Last updated: September 4, 2026

Earnline is an open-source, local-first income ledger. The public GitHub build
does not connect to a working production Supabase workspace and contains no
production credentials.

## Data kept on your device

The iPhone app stores the ledger locally with SwiftData. This can include client
names, projects, task descriptions, dates, payment status, income amounts,
currency settings, event notes, project-icon choices, and month reviews. App
Lock stores only its local security state in the iPhone Keychain. Face ID or the
device passcode is evaluated by iOS; Earnline does not receive or store biometric
data.

The camera is used only when you choose to scan a one-time device-pairing QR
code. Earnline does not save the camera image.

Before removing the app, you can create a full JSON backup from **Settings →
Data → Export or import backup**. If you signed in to an operator-configured
workspace, sign out first so Earnline can remove its local secure session.
Removing the app deletes its sandboxed ledger, but iOS Keychain items can
otherwise survive app removal.

## Optional cloud sync

Cloud sync is disabled in the unsigned public release unless a developer or
operator supplies a Supabase project. When it is configured, Earnline can send
the following to that operator's Supabase workspace:

- account email and authentication identifiers supplied by Google or GitHub;
- ledger financial information and user-entered content;
- workspace membership, sync timestamps, deletion tombstones, and paired-device
  identifiers;
- currency preferences, project icons, and month reviews.

That deployment's operator controls its Supabase project, OAuth configuration,
retention, backups, and deletion procedures. Review those terms before signing
in. Signing out removes the local session; it does not by itself erase the
operator's cloud copy.

## Tracking and sharing

Earnline contains no advertising SDK, analytics SDK, or cross-app tracking. The
project does not sell personal information. Data is shared only with services
needed for an operator-configured sync deployment: Supabase and the OAuth
provider selected at sign-in.

## Source and questions

The implementation and data contract are available in this repository. For a
private deployment, send data-access or deletion requests to the person or
organization operating that Supabase workspace.
