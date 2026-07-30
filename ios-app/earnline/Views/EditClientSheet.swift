import SwiftUI
import SwiftData

/// Edit a client — the compose-bar editing sheet (`sheetEditorHeader`: ✕
/// discards, ✓ commits) over the same name + color cards as `NewClientSheet`,
/// with the destructive action isolated in its own red row at the end. Edits
/// stay in local drafts until the ✓ commits them in one save, so cancel
/// really cancels; deletion confirms first and then hands off to the page,
/// which pops before removing the model.
struct EditClientSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(LedgerMutationStore.self) private var mutations
    @Environment(\.dynamicTypeSize) private var typeSize

    let client: Client
    /// Names of every *other* client — the duplicate check must not trip on
    /// the client's own current name.
    let otherClientNames: [String]
    /// Runs after the sheet closes; the page owns the pop-then-delete dance.
    var onDelete: () -> Void

    @State private var name: String
    @State private var colorHex: String
    @State private var confirmDelete = false
    @State private var saveError: String?
    /// Measured height of the content stack, used to size the sheet exactly —
    /// the same self-sizing contract as `NewClientSheet`.
    @State private var contentHeight: CGFloat = 420

    /// Fixed chrome around the scrollable content — the inline nav header and
    /// the home-indicator inset (no CTA dock: the ✓ commits from the bar).
    private let chrome: CGFloat = 96

    init(client: Client, otherClientNames: [String], onDelete: @escaping () -> Void) {
        self.client = client
        self.otherClientNames = otherClientNames
        self.onDelete = onDelete
        _name = State(initialValue: client.name)
        _colorHex = State(initialValue: client.colorHex)
    }

    private var validation: ClientNameValidation {
        Validation.validateClientName(name, existingNames: otherClientNames)
    }

    private var detents: Set<PresentationDetent> {
        typeSize.isAccessibilitySize ? [.large] : [.height(contentHeight + chrome)]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                nameChip
                nameSection
                colorSection
                deleteSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 6)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .background(Theme.background)
        .scrollDismissesKeyboard(.interactively)
        .sheetEditorHeader("Edit client",
                           saveEnabled: validation.validName != nil,
                           onCancel: { dismiss() },
                           onSave: save)
        .presentationDetents(detents)
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.background)
        .saveErrorAlert($saveError, title: "Could not save client")
        .alert("Delete \(client.name)?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                dismiss()
                onDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes \(client.entries.count) income line(s) on every synced device.")
        }
    }

    /// The live identity chip from the profile page, mirrored at the top of the
    /// editor so a rename or recolor previews instantly — the same glass capsule
    /// tinted with the draft color.
    private var nameChip: some View {
        Text(name.isEmpty ? " " : name)
            .appFont(24, .semibold, relativeTo: .title2)
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .glassEffect(.regular.tint(Color(hex: colorHex)).interactive(), in: .capsule)
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
            .padding(.bottom, 4)
            .accessibilityHidden(true)
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardHeader("Name")
            ChromeCard {
                ChromeRow(icon: "person.circle.fill") {
                    TextField("Client name", text: $name)
                        .appFont(17)
                        .onChange(of: name) { _, value in
                            name = Validation.capped(value, max: Limits.maxClientNameLength)
                        }
                        .onSubmit(save)
                }
            }
            if let message = validation.message {
                CardFootnote { Text(message).foregroundStyle(Theme.statusCanceled) }
            }
        }
    }

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardHeader("Color")
            ChromeCard {
                ClientColorGrid(selection: $colorHex)
            }
        }
    }

    /// Destructive action isolated in its own card — a single centered red row,
    /// as the Figma draws it. The confirmation alert carries the warning copy.
    private var deleteSection: some View {
        ChromeCard {
            Button { confirmDelete = true } label: {
                Text("Delete Client")
                    .appFont(17)
                    .foregroundStyle(Theme.statusCanceled)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    private func save() {
        guard let validName = validation.validName, !client.isDeleted else { return }
        guard validName != client.name || colorHex != client.colorHex else {
            dismiss()
            return
        }
        client.name = validName
        client.colorHex = colorHex
        client.markDirty()
        if let error = mutations.save(context) {
            saveError = error
        } else {
            dismiss()
        }
    }
}
