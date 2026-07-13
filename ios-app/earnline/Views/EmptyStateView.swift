import SwiftUI

struct EmptyStateView: View {
    var onStart: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Write your first line", systemImage: "pencil.and.scribble")
        } description: {
            Text("Jot income like a notebook —\n“$240 Acme: 2 screens”")
        } actions: {
            Button("New line", systemImage: "plus", action: onStart)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
    }
}
