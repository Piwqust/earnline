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
    @Environment(AppModel.self) private var app
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

    /// One namespace so the selection ring slides between swatches (matched
    /// geometry) — the same treatment as `NewClientSheet`.
    @Namespace private var swatchSelection

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 6)
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

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardHeader("Name")
            ChromeCard {
                ChromeRow {
                    Circle()
                        .fill(Color(hex: colorHex))
                        .frame(width: 12, height: 12)
                    TextField("Client name", text: $name)
                        .appFont(17, .medium)
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
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(Theme.clientPalette, id: \.self) { hex in
                        swatch(hex)
                    }
                }
                .padding(18)
            }
        }
    }

    /// Destructive action isolated in its own card — ChatGPT's "Log out" row.
    private var deleteSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ChromeCard {
                Button { confirmDelete = true } label: {
                    ChromeRow(icon: nil) {
                        Image(systemName: "trash")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(Theme.statusCanceled)
                            .frame(width: 24)
                        Text("Delete Client").foregroundStyle(Theme.statusCanceled)
                        Spacer()
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            CardFootnote {
                Text("Removes the client and all of its income lines everywhere.")
            }
        }
    }

    /// Palette swatch — the ChatGPT accent-picker treatment shared with
    /// `NewClientSheet`: an ink selection ring that springs between swatches.
    private func swatch(_ hex: String) -> some View {
        let selected = hex == colorHex
        return Circle()
            .fill(Color(hex: hex))
            .frame(height: 36)
            .overlay {
                Circle().strokeBorder(Theme.label(0.08), lineWidth: 0.5)
            }
            .overlay {
                if selected {
                    Circle()
                        .stroke(Theme.label(0.85), lineWidth: 2.5)
                        .padding(-4)
                        .matchedGeometryEffect(id: "swatchRing", in: swatchSelection)
                }
            }
            .scaleEffect(selected ? 1.08 : 1)
            .contentShape(.circle)
            .onTapGesture {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.62)) {
                    colorHex = hex
                }
                UISelectionFeedbackGenerator().selectionChanged()
            }
            .accessibilityLabel(Text("Color"))
            .accessibilityAddTraits(selected ? .isSelected : [])
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
        if let error = app.save(context) {
            saveError = error
        } else {
            dismiss()
        }
    }
}
