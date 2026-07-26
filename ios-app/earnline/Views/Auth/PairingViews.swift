import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit
import VisionKit

// MARK: - Pairing (redeem on the new device)

struct PairDeviceRedeemSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var manualCode = ""
    @State private var scannerMessage: String?

    private var canRedeem: Bool {
        !manualCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var pairingError: String? {
        guard case let .failure(message) = app.accountState else { return nil }
        return message
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 9) {
                        Text("Connect this device")
                            .font(.title2.weight(.bold))
                        Text("Scan the one-time QR code shown on your owner device. It expires in 10 minutes and can only be used once.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .multilineTextAlignment(.center)

                    scannerSection

                    HStack(spacing: 12) {
                        Rectangle().fill(Theme.hairline).frame(height: 1)
                        Text("OR")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Rectangle().fill(Theme.hairline).frame(height: 1)
                    }
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Pairing code", text: $manualCode)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .writingToolsBehavior(.disabled)
                            .textContentType(.oneTimeCode)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 52)
                            .background(Theme.surface, in: .rect(cornerRadius: 14, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Theme.chipStroke, lineWidth: 1)
                            }
                            .accessibilityLabel("Pairing code")
                        if let scannerMessage {
                            Label(scannerMessage, systemImage: "camera.slash")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if let pairingError {
                        PairingInlineNotice(label: "Couldn’t connect this device", message: pairingError)
                    }
                }
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
                .padding(20)
                .padding(.bottom, 80)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                PillCTA("Connect this device", isEnabled: canRedeem) {
                    Task { await app.redeemPairingCode(manualCode) }
                }
                .accessibilityIdentifier("auth.connectDevice")
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Theme.background)
            }
            .navigationTitle("Pair a device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var scannerSection: some View {
        if #available(iOS 16.0, *), DataScannerViewController.isSupported, DataScannerViewController.isAvailable {
            PairingCodeScanner(value: $manualCode, scannerMessage: $scannerMessage)
                .frame(height: 252)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .accessibilityLabel("Pairing code camera scanner")
        } else {
            Label("Camera scanning is unavailable. Enter the code below.", systemImage: "camera.slash")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.card, style: .continuous))
        }
    }
}

// MARK: - Settings-side account & pairing (unchanged design)

struct AccountDevicesSection: View {
    @Environment(AppModel.self) private var app
    @Binding var showingPairingCode: Bool
    @State private var showingSignOutConfirmation = false

    var body: some View {
        Section("Account & devices") {
            if let session = app.accountSession {
                LabeledContent("Account") {
                    Text(session.label)
                        .lineLimit(1)
                }
                LabeledContent("This device") {
                    Text(session.isLocalOnly ? "Local" : (session.isPairedDevice ? "Paired" : "Owner"))
                }
                if !session.isLocalOnly {
                    if session.isOwner {
                        Button {
                            showingPairingCode = true
                        } label: {
                            Label("Pair another device", systemImage: "qrcode")
                        }
                        .accessibilityHint("Shows a one-time QR code")

                        NavigationLink {
                            PairedDevicesView()
                        } label: {
                            Label("Manage paired devices", systemImage: "iphone.gen3")
                        }
                    }
                    Button("Sign out", role: .destructive) {
                        showingSignOutConfirmation = true
                    }
                }
            }
        }
        .confirmationDialog("Sign out of this device?", isPresented: $showingSignOutConfirmation, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { Task { await app.signOutAccount() } }
        } message: {
            Text("A paired device must scan a new code before it can sync again.")
        }
    }
}

struct PairingCodeDisplaySheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var pairingCode: AppModel.PairingCode?
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if let pairingCode {
                    ScrollView {
                        VStack(spacing: 20) {
                            VStack(spacing: 8) {
                                Text("Connect another device")
                                    .font(.title2.weight(.bold))
                                Text("Scan this code on the device you want to pair.")
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }

                            QRCodeImage(payload: pairingCode.payload)
                                .frame(width: 230, height: 230)
                                .accessibilityLabel("One-time device pairing QR code")

                            Text("Expires \(pairingCode.expiresAt, style: .relative) and can be used once.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)

                            Button("Generate a new code") { Task { await loadCode() } }
                                .buttonStyle(.glass)
                                .buttonBorderShape(.capsule)
                                .frame(minHeight: 44)
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity)
                    }
                } else if isLoading {
                    ProgressView("Creating a secure code…")
                } else {
                    ContentUnavailableView {
                        Label("Couldn’t create a code", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(errorMessage ?? "Try again.")
                    } actions: {
                        Button("Try again") { Task { await loadCode() } }
                    }
                }
            }
            .navigationTitle("Pair a device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await loadCode() }
    }

    private func loadCode() async {
        isLoading = true
        errorMessage = nil
        do {
            pairingCode = try await app.createPairingCode()
        } catch {
            pairingCode = nil
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private struct PairingInlineNotice: View {
    let label: LocalizedStringKey
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(Theme.statusProgress)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.statusProgress.opacity(0.30), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct QRCodeImage: View {
    let payload: String

    var body: some View {
        Group {
            if let image = makeImage(payload) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "qrcode")
                    .font(.system(size: 96))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        // QR codes need an opaque white quiet zone to remain scannable in every appearance.
        .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func makeImage(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scale = CGAffineTransform(scaleX: 10, y: 10)
        return UIImage(ciImage: output.transformed(by: scale))
    }
}

@available(iOS 16.0, *)
private struct PairingCodeScanner: UIViewControllerRepresentable {
    @Binding var value: String
    @Binding var scannerMessage: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value, scannerMessage: $scannerMessage)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        do {
            try controller.startScanning()
        } catch {
            scannerMessage = String(localized: "Camera access was not granted. You can enter the code manually.")
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        @Binding private var value: String
        @Binding private var scannerMessage: String?

        init(value: Binding<String>, scannerMessage: Binding<String?>) {
            _value = value
            _scannerMessage = scannerMessage
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard value.isEmpty,
                  let item = addedItems.first,
                  case let .barcode(code) = item,
                  let payload = code.payloadStringValue else { return }
            value = payload
            scannerMessage = nil
            dataScanner.stopScanning()
        }
    }
}
