import SwiftUI
import SwiftData

struct NewClientSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app

    let existingCount: Int
    var onCreate: (Client) -> Void

    @State private var name = ""
    @State private var colorHex: String

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 6)

    init(existingCount: Int, onCreate: @escaping (Client) -> Void) {
        self.existingCount = existingCount
        self.onCreate = onCreate
        _colorHex = State(initialValue: Theme.clientPalette[existingCount % Theme.clientPalette.count])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 8) {
                        Circle().fill(Color(hex: colorHex)).frame(width: 12, height: 12)
                        TextField("Client name", text: $name)
                            .font(.system(size: 17, weight: .medium))
                    }
                } header: { Text("Name") }

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
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func create() {
        let client = Client(name: name.trimmingCharacters(in: .whitespaces),
                            colorHex: colorHex,
                            sortIndex: existingCount)
        context.insert(client)
        try? context.save()
        app.queueSync(context: context)
        onCreate(client)
        dismiss()
    }
}
