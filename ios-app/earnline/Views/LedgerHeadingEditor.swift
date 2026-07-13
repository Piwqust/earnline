import SwiftUI

/// Focused editor for both heading creation and rename. It owns its transient
/// field/focus/confirmation state; `LedgerView` only receives typed outcomes.
struct LedgerHeadingEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    let allowsDeletion: Bool
    let onSave: (String) -> Bool
    let onDelete: (() -> Void)?

    @State private var title: String
    @State private var confirmsDeletion = false
    @FocusState private var titleFocused: Bool

    init(
        initialTitle: String,
        allowsDeletion: Bool,
        onSave: @escaping (String) -> Bool,
        onDelete: (() -> Void)? = nil
    ) {
        _title = State(initialValue: initialTitle)
        self.allowsDeletion = allowsDeletion
        self.onSave = onSave
        self.onDelete = onDelete
    }

    private var cleanTitle: String {
        Validation.trimmed(title, max: Limits.maxHeadingLength)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                ChromeCard {
                    ChromeRow(icon: "text.alignleft") {
                        TextField("Title", text: $title)
                            .focused($titleFocused)
                            .submitLabel(.done)
                            .onSubmit(save)
                            .appFont(17)
                    }
                }

                PillCTA("Save", isEnabled: !cleanTitle.isEmpty, action: save)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Theme.background)
            .navigationTitle("Heading")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if allowsDeletion {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { confirmsDeletion = true } label: {
                            Image(systemName: "trash")
                        }
                        .tint(Theme.statusCanceled)
                        .accessibilityLabel("Delete")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                        .tint(.primary)
                }
            }
            .alert("Delete heading?", isPresented: $confirmsDeletion) {
                Button("Delete", role: .destructive) {
                    onDelete?()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(cleanTitle.isEmpty ? String(localized: "Untitled") : cleanTitle)
            }
        }
        .presentationDetents(typeSize.isAccessibilitySize ? [.medium] : [.height(240)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.background)
        .task {
            try? await Task.sleep(for: .milliseconds(400))
            titleFocused = true
        }
    }

    private func save() {
        guard !cleanTitle.isEmpty, onSave(cleanTitle) else { return }
        dismiss()
    }
}
