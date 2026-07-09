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
                    .appFont(20, .semibold)
                    .foregroundStyle(Theme.label)
                Text("Jot income like a notebook —\n“$240 Acme: 2 screens”")
                    .appFont(15)
                    .foregroundStyle(Theme.label(0.5))
                    .multilineTextAlignment(.center)
            }

            Button(action: onStart) {
                Text("New line")
                    .appFont(16, .medium)
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
