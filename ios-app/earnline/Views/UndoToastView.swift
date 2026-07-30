import SwiftUI
import SwiftData

/// Bottom "Deleted · Undo" glass pill, visible while `LedgerMutationStore`
/// holds an undo snapshot. Hosted per-surface (ledger root, Pending sheet, client detail)
/// rather than once at the root — a root overlay would sit *under* presented
/// sheets.
struct UndoToastHost: ViewModifier {
    @Environment(LedgerMutationStore.self) private var mutations
    @Environment(\.modelContext) private var context
    @State private var undoError: String?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if mutations.undoableDelete != nil {
                    toast
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.25), value: mutations.undoableDelete == nil)
            .saveErrorAlert($undoError, title: "Could not restore")
    }

    private var toast: some View {
        HStack(spacing: 14) {
            Text("Deleted")
                .appFont(14)
                .foregroundStyle(.secondary)
            Button {
                undoError = mutations.performUndo(context: context)
            } label: {
                Text("Undo")
                    .appFont(15, .semibold)
                    .foregroundStyle(.tint)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Undo delete")
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 44)
        .glassEffect(.regular, in: .capsule)
        .padding(.bottom, 8)
    }
}

extension View {
    func undoToastHost() -> some View { modifier(UndoToastHost()) }
}
