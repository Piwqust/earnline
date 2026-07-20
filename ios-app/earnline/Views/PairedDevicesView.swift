import SwiftUI

struct PairedDevicesView: View {
    @Environment(AppModel.self) private var app

    @State private var devices: [AppModel.PairedDevice] = []
    @State private var pendingRemoval: AppModel.PairedDevice?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            if devices.isEmpty, !isLoading, errorMessage == nil {
                ContentUnavailableView(
                    "No paired devices",
                    systemImage: "iphone.slash",
                    description: Text("Generate a one-time code from Account & Devices to connect another device.")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(devices) { device in
                    PairedDeviceRow(device: device)
                        .swipeActions {
                            Button("Remove", role: .destructive) {
                                pendingRemoval = device
                            }
                        }
                }
            }
        }
        .overlay {
            if isLoading { ProgressView("Loading devices…") }
        }
        .navigationTitle("Paired devices")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await loadDevices() }
        .task { await loadDevices() }
        .confirmationDialog(
            "Remove this device?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove device", role: .destructive) {
                guard let device = pendingRemoval else { return }
                pendingRemoval = nil
                Task { await remove(device) }
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text("The device will be signed out and must scan a new code before it can sync again.")
        }
        .alert("Couldn’t update devices", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Try again") { Task { await loadDevices() } }
            Button("Cancel", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Try again.")
        }
    }

    private func loadDevices() async {
        isLoading = true
        do {
            devices = try await app.pairedDevices()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func remove(_ device: AppModel.PairedDevice) async {
        do {
            try await app.revokePairedDevice(device)
            devices.removeAll { $0.id == device.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct PairedDeviceRow: View {
    let device: AppModel.PairedDevice

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "iphone.gen3")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("Paired device")
                    .font(.body)
                if let lastSignInAt = device.lastSignInAt {
                    Text("Last signed in \(lastSignInAt, style: .relative)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Added \(device.createdAt, style: .relative)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Swipe left to remove this device")
    }
}
