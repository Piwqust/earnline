import SwiftUI

struct EmptyStateView: View {
    var onStart: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "pencil.and.scribble")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.label(0.35))
                .frame(width: 72, height: 72)
                .glassEffect(.regular, in: .circle)

            VStack(spacing: 6) {
                Text("Write your first line")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.label)
                Text("Jot income like a notebook —\n“$240 Acme: 2 screens”")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.label(0.5))
                    .multilineTextAlignment(.center)
            }

            Button(action: onStart) {
                Text("New line")
                    .font(.system(size: 16, weight: .medium))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.glass)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
}
