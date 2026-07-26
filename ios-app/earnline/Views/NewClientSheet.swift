import SwiftUI
import SwiftData

/// Create a client — ChatGPT's "New project" sheet shape: centered title with
/// a circular glass ✕, white input card on the gray sheet, and one accent pill
/// CTA. The sheet measures its own content and sizes to it (`detents`), so the
/// CTA sits just beneath the color card instead of floating over a slab of dead
/// space. The empty-name error only appears once the field has been touched.
struct NewClientSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize

    let existingClients: [Client]
    var onCreate: (Client) -> Void

    @State private var name = ""
    @State private var colorHex: String
    /// Stays false until the field is first edited, so a freshly opened sheet
    /// never scolds the user with "Enter a client name" before they've typed.
    @State private var hasEdited = false
    @State private var saveError: String?
    /// Measured height of the content stack, used to size the sheet exactly.
    @State private var contentHeight: CGFloat = 300

    private var existingCount: Int { existingClients.count }
    private var validation: ClientNameValidation {
        Validation.validateClientName(name, existingNames: existingClients.map(\.name))
    }
    /// Show the validation message only after the field has been touched.
    private var shownMessage: String? { hasEdited ? validation.message : nil }

    /// Fixed chrome around the scrollable content — the inline nav header, the
    /// docked CTA, and the home-indicator inset. Added to the measured content
    /// height so the sheet is exactly as tall as it needs to be.
    private let chrome: CGFloat = 146

    private var detents: Set<PresentationDetent> {
        // At accessibility text sizes the content outgrows any fixed height, so
        // fall back to a scrollable large detent rather than clipping.
        typeSize.isAccessibilitySize ? [.large] : [.height(contentHeight + chrome)]
    }

    init(existingClients: [Client], onCreate: @escaping (Client) -> Void) {
        self.existingClients = existingClients
        self.onCreate = onCreate
        _colorHex = State(initialValue: Theme.clientPalette[existingClients.count % Theme.clientPalette.count])
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                nameSection
                colorSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 6)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .background(Theme.background)
        .scrollDismissesKeyboard(.interactively)
        .sheetHeader("New client", onClose: { dismiss() })
        .sheetFooter {
            PillCTA("Add client", isEnabled: validation.validName != nil, action: create)
                .accessibilityIdentifier("client.create")
        }
        .presentationDetents(detents)
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.background)
        .saveErrorAlert($saveError, title: "Could not save client")
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardHeader("Name")
            ChromeCard {
                ChromeRow(icon: "person.circle.fill") {
                    TextField("Client name", text: $name)
                        .appFont(17)
                        .onChange(of: name) { _, value in
                            hasEdited = true
                            name = Validation.capped(value, max: Limits.maxClientNameLength)
                        }
                }
            }
            if let message = shownMessage {
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

    private func create() {
        guard let validName = validation.validName else { return }
        let client = Client(name: validName, colorHex: colorHex, sortIndex: existingCount)
        context.insert(client)
        if let error = app.save(context) {
            saveError = error
        } else {
            onCreate(client)
            dismiss()
        }
    }
}
