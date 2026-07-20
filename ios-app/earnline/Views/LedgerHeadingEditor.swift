import SwiftUI

/// Focused editor for a dated event note. Its storage model remains `Heading`
/// for sync compatibility, while the product only exposes a useful note.
struct LedgerHeadingEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    let allowsDeletion: Bool
    let onSave: (String, Date) -> Bool
    let onDelete: (() -> Void)?

    @State private var title: String
    @State private var date: Date
    @State private var confirmsDeletion = false
    @FocusState private var titleFocused: Bool

    init(
        initialTitle: String,
        initialDate: Date,
        allowsDeletion: Bool,
        onSave: @escaping (String, Date) -> Bool,
        onDelete: (() -> Void)? = nil
    ) {
        _title = State(initialValue: initialTitle)
        _date = State(initialValue: initialDate)
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
                    VStack(spacing: 0) {
                        ChromeRow(icon: "note.text") {
                            TextField("Note", text: $title)
                                .focused($titleFocused)
                                .submitLabel(.done)
                                .onSubmit(save)
                                .appFont(17)
                        }
                        ChromeDivider(inset: 16)
                        ChromeRow(icon: "calendar") {
                            DatePicker("Date", selection: $date, displayedComponents: .date)
                                .tint(Theme.blue)
                        }
                    }
                }

                PillCTA("Save", isEnabled: !cleanTitle.isEmpty, action: save)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Theme.background)
            .navigationTitle(allowsDeletion ? "Edit event note" : "New event note")
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
            .alert("Delete event note?", isPresented: $confirmsDeletion) {
                Button("Delete", role: .destructive) {
                    onDelete?()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(cleanTitle.isEmpty ? String(localized: "Untitled") : cleanTitle)
            }
        }
        .presentationDetents(typeSize.isAccessibilitySize ? [.medium] : [.height(300)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.background)
        .task {
            try? await Task.sleep(for: .milliseconds(400))
            titleFocused = true
        }
    }

    private func save() {
        guard !cleanTitle.isEmpty, onSave(cleanTitle, date) else { return }
        dismiss()
    }
}
