import SwiftUI
import UIKit

/// The preview displays the exact PNG files the user will share. It never
/// screenshots the live app, so a sync/update cannot change the image between
/// preview and the native system Share Sheet.
@MainActor
struct ReportPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let snapshotFactory: () -> ReportSnapshot
    let onCloseMonth: ((String) -> String?)?
    let onReopenMonth: (() -> String?)?

    @State private var snapshot: ReportSnapshot
    @State private var renderResult: ReportCardRenderResult?
    @State private var isRendering = false
    @State private var renderError: String?
    @State private var presentsShareSheet = false
    @State private var presentsMonthReviewEditor = false
    @State private var actionError: String?
    @State private var renderRevision = 0

    init(
        snapshot: ReportSnapshot,
        onCloseMonth: ((String) -> String?)? = nil,
        onReopenMonth: (() -> String?)? = nil,
        snapshotFactory: (() -> ReportSnapshot)? = nil
    ) {
        self.onCloseMonth = onCloseMonth
        self.onReopenMonth = onReopenMonth
        self.snapshotFactory = snapshotFactory ?? { snapshot }
        _snapshot = State(initialValue: snapshot)
    }

    private var isPersonalMonthlyReport: Bool {
        snapshot.audience == .personal && snapshot.scope.isMonth
    }

    var body: some View {
        NavigationStack {
            Group {
                if isRendering && renderResult == nil {
                    renderingState
                } else if let renderError {
                    renderingErrorState(renderError)
                } else if let renderResult {
                    previewContent(renderResult.cards)
                } else {
                    renderingState
                }
            }
            .navigationTitle("Report preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .close) { dismiss() }
                        .tint(.primary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: shareReport) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(renderResult == nil)
                    .accessibilityLabel("Share report")
                    .accessibilityIdentifier("report.share")
                }
            }
        }
        .task(id: renderRevision) {
            await renderCards()
        }
        .sheet(isPresented: $presentsShareSheet) {
            if let urls = renderResult?.export.fileURLs {
                NativeActivitySheet(activityItems: urls) {
                    presentsShareSheet = false
                }
            }
        }
        .sheet(isPresented: $presentsMonthReviewEditor) {
            MonthReviewNoteEditor(
                initialNote: snapshot.monthReview?.note ?? "",
                onSave: closeMonth
            )
        }
        .saveErrorAlert($actionError, title: "Could not update month review")
        .onDisappear {
            // The activity sheet gets the same URLs while this preview stays
            // mounted. When the preview itself goes away, the temporary files
            // are no longer needed and can be reclaimed safely.
            if !presentsShareSheet { cleanRenderedFiles() }
        }
        .accessibilityIdentifier("report.preview")
    }

    private var renderingState: some View {
        ContentUnavailableView {
            Label("Rendering report", systemImage: "photo.stack")
        } description: {
            Text("Preparing shareable PNG cards…")
        }
        .accessibilityIdentifier("report.rendering")
    }

    private func renderingErrorState(_ error: String) -> some View {
        VStack(spacing: 16) {
            ContentUnavailableView {
                Label("Couldn’t render report", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            }
            Button("Try again") { renderRevision &+= 1 }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .accessibilityIdentifier("report.renderError")
    }

    private func previewContent(_ cards: [ReportRenderedCard]) -> some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                reportSummary

                ForEach(cards) { card in
                    VStack(alignment: .leading, spacing: 8) {
                        Image(uiImage: card.image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(.rect(cornerRadius: 16))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(.quaternary, lineWidth: 1)
                            }
                            .shadow(color: .black.opacity(colorScheme == .dark ? 0.28 : 0.10), radius: 10, y: 4)
                            .accessibilityLabel("Report card \(card.pageIndex) of \(card.pageCount)")
                        if cards.count > 1 {
                            Text("Card \(card.pageIndex) of \(card.pageCount)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if isPersonalMonthlyReport {
                    monthReviewControls
                }
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
    }

    private var reportSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(reportTitle)
                .font(.headline)
            Text(reportPeriod)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("These are the exact PNG cards that will be shared.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var monthReviewControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            if snapshot.monthReview?.isClosed == true {
                Label("Month closed", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(Theme.label)
                if let note = snapshot.monthReview?.note.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                    Text(note)
                        .foregroundStyle(.secondary)
                }
                Button("Reopen month", role: .destructive, action: reopenMonth)
                    .accessibilityIdentifier("report.reopenMonth")
            } else {
                Text("Finish this month")
                    .font(.headline)
                Text("Closing is a soft review. You can still edit ledger rows later, and reopen this month at any time.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Close month") {
                    presentsMonthReviewEditor = true
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("report.closeMonth")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: .rect(cornerRadius: 16))
    }

    private var reportTitle: String {
        switch snapshot.audience {
        case .personal: String(localized: "Monthly report")
        case .client(_, let name): String(localized: "Report for \(name)")
        }
    }

    private var reportPeriod: String {
        if snapshot.scope.isMonth {
            return DateFormat.monthAndYear(snapshot.period.start)
        }
        let end = Calendar.current.date(byAdding: .day, value: -1, to: snapshot.period.endExclusive)
            ?? snapshot.period.endExclusive
        return "\(DateFormat.dotted(snapshot.period.start)) – \(DateFormat.dotted(end))"
    }

    private func renderCards() async {
        cleanRenderedFiles()
        isRendering = true
        renderError = nil
        await Task.yield()
        guard !Task.isCancelled else { return }

        do {
            let appearance: ReportCardAppearance = colorScheme == .dark ? .dark : .paper
            let result = try ReportCardRenderer.render(
                snapshot: snapshot,
                options: ReportCardRenderingOptions(appearance: appearance)
            )
            guard !Task.isCancelled else {
                try? result.export.removeFiles()
                return
            }
            renderResult = result
        } catch {
            renderError = error.localizedDescription
        }
        isRendering = false
    }

    private func shareReport() {
        guard renderResult != nil else { return }
        presentsShareSheet = true
    }

    private func closeMonth(_ note: String) {
        guard let onCloseMonth else { return }
        if let error = onCloseMonth(note) {
            actionError = error
            return
        }
        snapshot = snapshotFactory()
        renderRevision &+= 1
    }

    private func reopenMonth() {
        guard let onReopenMonth else { return }
        if let error = onReopenMonth() {
            actionError = error
            return
        }
        snapshot = snapshotFactory()
        renderRevision &+= 1
    }

    private func cleanRenderedFiles() {
        guard let export = renderResult?.export else { return }
        try? export.removeFiles()
        renderResult = nil
    }
}

private struct MonthReviewNoteEditor: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: (String) -> Void
    @State private var note: String

    init(initialNote: String, onSave: @escaping (String) -> Void) {
        self.onSave = onSave
        _note = State(initialValue: initialNote)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $note)
                        .frame(minHeight: 130)
                        .accessibilityLabel("Month review note")
                } header: {
                    Text("Month note")
                } footer: {
                    Text("Optional. This stays in your personal monthly report and is never included in a client report.")
                }
            }
            .navigationTitle("Close month")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") {
                        onSave(note.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                }
            }
        }
    }
}

/// A focused selector used only before a client-facing report. It deliberately
/// offers no personal analytics controls: the resulting snapshot is filtered
/// to this client by `ReportAudience.client`.
struct ClientReportScopePicker: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case month
        case range

        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .month: "Month"
            case .range: "Date range"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    let clientName: String
    let onContinue: (ReportScope) -> Void

    @State private var mode: Mode = .month
    @State private var month = Date()
    @State private var rangeStart = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    @State private var rangeEnd = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Period", selection: $mode) {
                        ForEach(Mode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                switch mode {
                case .month:
                    Section {
                        DatePicker("Month", selection: $month, displayedComponents: .date)
                    } header: {
                        Text("Month")
                    } footer: {
                        Text("The report includes all work for the selected calendar month.")
                    }
                case .range:
                    Section {
                        DatePicker("From", selection: $rangeStart, displayedComponents: .date)
                        DatePicker("Through", selection: $rangeEnd, displayedComponents: .date)
                    } header: {
                        Text("Date range")
                    } footer: {
                        Text("Both selected dates are included.")
                    }
                }
            }
            .navigationTitle("Report for \(clientName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Preview") {
                        onContinue(scope)
                    }
                    .accessibilityIdentifier("client.report.scope.preview")
                }
            }
        }
    }

    private var scope: ReportScope {
        switch mode {
        case .month: .month(containing: month)
        case .range: .dateRange(start: rangeStart, end: rangeEnd)
        }
    }
}

private struct NativeActivitySheet: UIViewControllerRepresentable {
    let activityItems: [URL]
    let onComplete: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            DispatchQueue.main.async {
                onComplete()
            }
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
