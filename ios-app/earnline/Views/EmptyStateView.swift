import SwiftUI

/// Hand-rolled rather than `ContentUnavailableView`: inside the ledger's
/// List row the system component stretches its action button to fill the
/// whole remaining viewport (iOS 26), which reads as a broken giant pill —
/// especially under the first-run tour's spotlight.
struct EmptyStateView: View {
    var onStart: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "pencil.and.scribble")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.bottom, 6)
                .accessibilityHidden(true)
            Text("Write your first line")
                .font(.title3.weight(.semibold))
            Text("Jot income like a notebook —\n“$240 Acme: 2 screens”")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("New line", systemImage: "plus", action: onStart)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.regular)
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
