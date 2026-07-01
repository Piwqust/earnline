import SwiftUI
import SwiftData

struct NewClientSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app

    let existingClients: [Client]
    var onCreate: (Client) -> Void

    @State private var name = ""
    @State private var colorHex: String
    @State private var saveError: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 6)
    private var existingCount: Int { existingClients.count }
    private var validation: ClientNameValidation {
        Validation.validateClientName(name, existingNames: existingClients.map(\.name))
    }

    init(existingClients: [Client], onCreate: @escaping (Client) -> Void) {
        self.existingClients = existingClients
        self.onCreate = onCreate
        _colorHex = State(initialValue: Theme.clientPalette[existingClients.count % Theme.clientPalette.count])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 8) {
                        Circle().fill(Color(hex: colorHex)).frame(width: 12, height: 12)
                        TextField("Client name", text: $name)
                            .font(.system(size: 17, weight: .medium))
                            .onChange(of: name) { _, value in
                                name = Validation.capped(value, max: Limits.maxClientNameLength)
                            }
                    }
                } header: { Text("Name") } footer: {
                    if let message = validation.message {
                        Text(message).foregroundStyle(.red)
                    }
                }

                Section {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(Theme.clientPalette, id: \.self) { hex in
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(height: 32)
                                .overlay {
                                    if hex == colorHex {
                                        Circle().strokeBorder(.white, lineWidth: 2)
                                            .padding(2)
                                    }
                                }
                                .overlay {
                                    Circle().strokeBorder(Theme.label(0.08), lineWidth: 0.5)
                                }
                                .onTapGesture { colorHex = hex }
                        }
                    }
                    .padding(.vertical, 4)
                } header: { Text("Color") }
            }
            .navigationTitle("New Client")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: create)
                        .disabled(validation.validName == nil)
                }
            }
        }
        .presentationDetents([.medium])
        .alert("Could not save client", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "Try again.")
        }
    }

    private func create() {
        guard let validName = validation.validName else { return }
        let client = Client(name: validName, colorHex: colorHex, sortIndex: existingCount)
        context.insert(client)
        do {
            try context.save()
            app.queueSync(context: context)
            onCreate(client)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
