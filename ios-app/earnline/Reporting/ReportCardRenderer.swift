import Foundation
import SwiftUI
import UIKit

/// Shareable reports deliberately use a self-contained paper or dark canvas
/// instead of mirroring the transient sheet chrome around the preview.
enum ReportCardAppearance: Sendable {
    case paper
    case dark
}

struct ReportCardRenderingOptions: Sendable {
    var appearance: ReportCardAppearance

    init(appearance: ReportCardAppearance = .paper) {
        self.appearance = appearance
    }
}

/// Stable URLs suitable for a system activity sheet. The caller owns cleanup:
/// this module never removes a file after handing it to `UIActivityViewController`.
struct ReportCardExport: Sendable {
    let fileURLs: [URL]

    func removeFiles() throws {
        for url in fileURLs where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

/// A rendered page for a SwiftUI preview plus its exact PNG file for sharing.
@MainActor
struct ReportRenderedCard: Identifiable {
    let id: UUID
    let pageIndex: Int
    let pageCount: Int
    let image: UIImage
    let url: URL
}

@MainActor
struct ReportCardRenderResult {
    let cards: [ReportRenderedCard]
    let export: ReportCardExport
}

enum ReportCardRenderingError: LocalizedError {
    case imageUnavailable
    case pngEncodingFailed

    var errorDescription: String? {
        switch self {
        case .imageUnavailable:
            return String(localized: "Could not render the report image.")
        case .pngEncodingFailed:
            return String(localized: "Could not encode the report image.")
        }
    }
}

/// Creates 1080×1350 PNG report cards. The renderer owns pagination so a long
/// ledger becomes more cards instead of clipping below the image boundary.
@MainActor
enum ReportCardRenderer {
    static let imageSize = CGSize(width: 1_080, height: 1_350)

    static func render(
        snapshot: ReportSnapshot,
        options: ReportCardRenderingOptions = .init(),
        directory: URL? = nil
    ) throws -> ReportCardRenderResult {
        let pages = pageModels(for: snapshot)
        let outputDirectory = directory ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("earnline-report-cards", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let batchID = UUID().uuidString.lowercased()
        var rendered: [ReportRenderedCard] = []
        var writtenURLs: [URL] = []

        do {
            for (index, page) in pages.enumerated() {
                let content = ReportCardPageView(
                    snapshot: snapshot,
                    page: page,
                    pageIndex: index + 1,
                    pageCount: pages.count,
                    appearance: options.appearance
                )
                .frame(width: imageSize.width, height: imageSize.height)

                let renderer = ImageRenderer(content: content)
                renderer.proposedSize = ProposedViewSize(width: imageSize.width, height: imageSize.height)
                renderer.scale = 1
                guard let image = renderer.uiImage else {
                    throw ReportCardRenderingError.imageUnavailable
                }
                guard let data = image.pngData() else {
                    throw ReportCardRenderingError.pngEncodingFailed
                }

                let url = outputDirectory.appendingPathComponent(
                    "earnline-report-\(batchID)-\(index + 1).png",
                    isDirectory: false
                )
                try data.write(to: url, options: .atomic)
                writtenURLs.append(url)
                rendered.append(ReportRenderedCard(
                    id: UUID(),
                    pageIndex: index + 1,
                    pageCount: pages.count,
                    image: image,
                    url: url
                ))
            }
        } catch {
            for url in writtenURLs {
                // A rendering failure can only leave temporary report files;
                // clean them up without masking the actionable original error.
                try? FileManager.default.removeItem(at: url)
            }
            throw error
        }

        return ReportCardRenderResult(
            cards: rendered,
            export: ReportCardExport(fileURLs: writtenURLs)
        )
    }

    private static func pageModels(for snapshot: ReportSnapshot) -> [ReportCardPage] {
        let timeline = timelineItems(for: snapshot)
        let timelinePages = paginate(timeline)
        return [.summary] + timelinePages.map { .timeline($0) }
    }

    private static func timelineItems(for snapshot: ReportSnapshot) -> [ReportTimelineItem] {
        let entryItems = snapshot.entries.flatMap { entry in
            textFragments(entry.task).enumerated().map { index, fragment in
                ReportTimelineItem.entry(
                    entry,
                    text: fragment,
                    isContinuation: index > 0,
                    fragmentIndex: index
                )
            }
        }
        let noteItems = snapshot.eventNotes.flatMap { note in
            textFragments(note.text).enumerated().map { index, fragment in
                ReportTimelineItem.note(
                    note,
                    text: fragment,
                    isContinuation: index > 0,
                    fragmentIndex: index
                )
            }
        }
        return (entryItems + noteItems).sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date < rhs.date }
            if lhs.sortPriority != rhs.sortPriority { return lhs.sortPriority < rhs.sortPriority }
            return lhs.id < rhs.id
        }
    }

    /// A fragment stays small enough for a predictable card row. A very long
    /// work description is therefore continued on the next card rather than
    /// truncated or made illegibly small.
    private static func textFragments(_ text: String, maximumCharacters: Int = 170) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maximumCharacters else { return [trimmed] }

        var fragments: [String] = []
        var remaining = trimmed[...]
        while remaining.count > maximumCharacters {
            let tentativeEnd = remaining.index(remaining.startIndex, offsetBy: maximumCharacters)
            let prefix = remaining[..<tentativeEnd]
            if let split = prefix.lastIndex(where: { $0.isWhitespace }) {
                fragments.append(String(remaining[..<split]).trimmingCharacters(in: .whitespacesAndNewlines))
                remaining = remaining[remaining.index(after: split)...]
            } else {
                fragments.append(String(prefix))
                remaining = remaining[tentativeEnd...]
            }
        }
        let tail = String(remaining).trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { fragments.append(tail) }
        return fragments.isEmpty ? [trimmed] : fragments
    }

    private static func paginate(_ items: [ReportTimelineItem]) -> [[ReportTimelineItem]] {
        let maximumUnits = 14
        var pages: [[ReportTimelineItem]] = []
        var current: [ReportTimelineItem] = []
        var usedUnits = 0

        for item in items {
            if !current.isEmpty, usedUnits + item.heightUnits > maximumUnits {
                pages.append(current)
                current = []
                usedUnits = 0
            }
            current.append(item)
            usedUnits += item.heightUnits
        }
        if !current.isEmpty { pages.append(current) }
        return pages
    }
}

private enum ReportCardPage {
    case summary
    case timeline([ReportTimelineItem])
}

private struct ReportTimelineItem: Identifiable {
    private enum Kind {
        case entry(entry: ReportEntry, text: String, isContinuation: Bool)
        case note(note: ReportEventNote, text: String, isContinuation: Bool)
    }

    let id: String
    let date: Date
    let sortPriority: Int
    let heightUnits: Int
    private let kind: Kind

    static func entry(
        _ entry: ReportEntry,
        text: String,
        isContinuation: Bool,
        fragmentIndex: Int
    ) -> ReportTimelineItem {
        ReportTimelineItem(
            id: "entry-\(entry.id.uuidString)-\(fragmentIndex)",
            date: entry.date,
            sortPriority: 1,
            heightUnits: isContinuation ? 2 : 3,
            kind: .entry(entry: entry, text: text, isContinuation: isContinuation)
        )
    }

    static func note(
        _ note: ReportEventNote,
        text: String,
        isContinuation: Bool,
        fragmentIndex: Int
    ) -> ReportTimelineItem {
        ReportTimelineItem(
            id: "note-\(note.id.uuidString)-\(fragmentIndex)",
            date: note.date,
            sortPriority: 0,
            heightUnits: 2,
            kind: .note(note: note, text: text, isContinuation: isContinuation)
        )
    }

    @ViewBuilder
    func view(palette: ReportCardPalette) -> some View {
        switch kind {
        case let .entry(entry, text, isContinuation):
            ReportTimelineEntryRow(entry: entry, text: text, isContinuation: isContinuation, palette: palette)
        case let .note(note, text, isContinuation):
            ReportTimelineNoteRow(note: note, text: text, isContinuation: isContinuation, palette: palette)
        }
    }
}

private struct ReportCardPalette {
    let canvas: Color
    let surface: Color
    let ink: Color
    let muted: Color
    let hairline: Color
    let blue: Color
    let paid: Color
    let progress: Color
    let canceled: Color

    init(appearance: ReportCardAppearance) {
        switch appearance {
        case .paper:
            canvas = Color(red: 0.95, green: 0.95, blue: 0.97)
            surface = .white
            ink = Color(red: 0.10, green: 0.10, blue: 0.11)
            muted = Color(red: 0.39, green: 0.39, blue: 0.42)
            hairline = Color.black.opacity(0.10)
            blue = Color(red: 0, green: 0.53, blue: 1)
            paid = Color(red: 0.42, green: 0.42, blue: 0.45)
            progress = Color(red: 1, green: 0.45, blue: 0.02)
            canceled = Color(red: 1, green: 0.23, blue: 0.19)
        case .dark:
            canvas = Color(red: 0.05, green: 0.05, blue: 0.06)
            surface = Color(red: 0.11, green: 0.11, blue: 0.12)
            ink = Color(red: 0.95, green: 0.95, blue: 0.96)
            muted = Color(red: 0.65, green: 0.65, blue: 0.68)
            hairline = Color.white.opacity(0.13)
            blue = Color(red: 0.23, green: 0.64, blue: 1)
            paid = Color(red: 0.66, green: 0.66, blue: 0.69)
            progress = Color(red: 1, green: 0.59, blue: 0.18)
            canceled = Color(red: 1, green: 0.40, blue: 0.36)
        }
    }
}

private struct ReportCardPageView: View {
    let snapshot: ReportSnapshot
    let page: ReportCardPage
    let pageIndex: Int
    let pageCount: Int
    let appearance: ReportCardAppearance

    private var palette: ReportCardPalette { .init(appearance: appearance) }

    var body: some View {
        ZStack {
            palette.canvas
            VStack(alignment: .leading, spacing: 0) {
                cardHeader

                switch page {
                case .summary:
                    ReportSummaryPage(snapshot: snapshot, palette: palette)
                case let .timeline(items):
                    ReportTimelinePage(items: items, palette: palette)
                }

                Spacer(minLength: 0)
                footer
            }
            .padding(64)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var cardHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(palette.muted)
                Text(periodTitle)
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(palette.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 24)
            Image(systemName: "arrow.up.right.square.fill")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(palette.blue)
                .accessibilityHidden(true)
        }
        .padding(.bottom, 38)
    }

    private var footer: some View {
        HStack {
            Text("earn›line")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(palette.ink)
            Spacer()
            Text("\(pageIndex) / \(pageCount)")
                .font(.system(size: 18, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.muted)
        }
        .padding(.top, 30)
    }

    private var title: String {
        switch snapshot.audience {
        case .personal:
            return String(localized: "Monthly report")
        case let .client(_, name):
            return name.isEmpty ? String(localized: "Client report") : name
        }
    }

    private var periodTitle: String {
        switch snapshot.scope {
        case .month:
            return snapshot.period.start.formatted(.dateTime.month(.wide).year())
        case .dateRange:
            return "\(snapshot.period.start.formatted(dateFormat)) – \(lastDay.formatted(dateFormat))"
        }
    }

    private var lastDay: Date {
        Calendar.current.date(byAdding: .day, value: -1, to: snapshot.period.endExclusive) ?? snapshot.period.endExclusive
    }

    private var dateFormat: Date.FormatStyle {
        .dateTime.day().month(.abbreviated).year()
    }

    private var accessibilityLabel: String {
        "\(title), \(periodTitle), page \(pageIndex) of \(pageCount)"
    }
}

private struct ReportSummaryPage: View {
    let snapshot: ReportSnapshot
    let palette: ReportCardPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            overview
            statusSummary
            if let lastYear = snapshot.lastYearComparison {
                lastYearSummary(lastYear)
            }
            if let review = snapshot.monthReview, review.isClosed {
                monthReview(review)
            }
        }
    }

    private var overview: some View {
        ReportCardSurface(palette: palette) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Original currencies")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(palette.ink)
                    Spacer()
                    Text(summaryCount)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(palette.muted)
                }
                Text("Generated \(snapshot.generatedAt.formatted(.dateTime.day().month(.abbreviated).year().hour().minute()))")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(palette.muted)
                CurrencyTotalsList(totals: snapshot.originalCurrencyTotals, palette: palette)

                if let usd = snapshot.usdEquivalent {
                    ReportHairline(palette: palette)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("USD equivalent at current rate")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(palette.muted)
                        Text(CurrencyFormatter.string(usd.amount, code: "USD"))
                            .font(.system(size: 40, weight: .bold).monospacedDigit())
                            .foregroundStyle(palette.ink)
                        if !usd.excludedCurrencyTotals.isEmpty {
                            Text(excludedText(usd.excludedCurrencyTotals))
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(palette.progress)
                        }
                    }
                } else {
                    ReportHairline(palette: palette)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("USD equivalent unavailable")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(palette.ink)
                        Text("USD is not selected as a conversion currency in Settings. Original totals above are unchanged.")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(palette.muted)
                    }
                }
            }
        }
    }

    private var summaryCount: String {
        switch snapshot.audience {
        case .personal:
            return "\(snapshot.clientCount) clients · \(snapshot.includedEntryCount) lines"
        case .client:
            return "\(snapshot.includedEntryCount) lines"
        }
    }

    private var statusSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 18) {
                StatusCard(
                    title: "Paid",
                    symbol: "checkmark.circle.fill",
                    total: snapshot.paid,
                    color: palette.paid,
                    palette: palette
                )
                StatusCard(
                    title: "In progress",
                    symbol: "clock.fill",
                    total: snapshot.inProgress,
                    color: palette.progress,
                    palette: palette
                )
            }
            if snapshot.canceledEntryCount > 0 {
                Label(
                    "\(snapshot.canceledEntryCount) canceled \(snapshot.canceledEntryCount == 1 ? "line is" : "lines are") excluded from totals",
                    systemImage: "xmark.circle.fill"
                )
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(palette.canceled)
            }
        }
    }

    private func lastYearSummary(_ comparison: ReportLastYearComparison) -> some View {
        ReportCardSurface(palette: palette) {
            VStack(alignment: .leading, spacing: 12) {
                Text("This month last year")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(palette.ink)
                Text(comparison.period.start.formatted(.dateTime.month(.wide).year()))
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(palette.muted)
                ForEach(comparison.currencyChanges) { change in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(change.currencyCode)
                                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                                .foregroundStyle(palette.ink)
                            Spacer()
                            Text(signed(CurrencyFormatter.string(change.difference, code: change.currencyCode), value: change.difference))
                                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                                .foregroundStyle(change.difference < 0 ? palette.canceled : palette.ink)
                        }
                        Text("\(CurrencyFormatter.string(change.current, code: change.currencyCode)) this month · \(CurrencyFormatter.string(change.previous, code: change.currencyCode)) last year")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(palette.muted)
                    }
                }
                if let usd = comparison.usdEquivalent {
                    ReportHairline(palette: palette)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("USD equivalent: \(signed(CurrencyFormatter.string(usd.difference, code: "USD"), value: usd.difference))")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(usd.difference < 0 ? palette.canceled : palette.ink)
                        Text("\(CurrencyFormatter.string(usd.current, code: "USD")) this month · \(CurrencyFormatter.string(usd.previous, code: "USD")) last year")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(palette.muted)
                    }
                }
            }
        }
    }

    private func monthReview(_ review: ReportMonthReview) -> some View {
        ReportCardSurface(palette: palette) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Month closed", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(palette.ink)
                if !review.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(review.note)
                        .font(.system(size: 18))
                        .foregroundStyle(palette.muted)
                        .lineLimit(4)
                }
            }
        }
    }

    private func excludedText(_ totals: [ReportCurrencyTotal]) -> String {
        let amounts = totals.map { CurrencyFormatter.string($0.amount, code: $0.currencyCode) }.joined(separator: " · ")
        return "Not included in USD equivalent: \(amounts)"
    }

    private func signed(_ text: String, value: Decimal) -> String {
        value > 0 ? "+\(text)" : text
    }
}

private struct ReportTimelinePage: View {
    let items: [ReportTimelineItem]
    let palette: ReportCardPalette

    var body: some View {
        ReportCardSurface(palette: palette) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Work & payments")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(palette.ink)
                    .padding(.bottom, 12)

                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { ReportHairline(palette: palette) }
                    item.view(palette: palette)
                        .padding(.vertical, 16)
                }
            }
        }
    }
}

private struct ReportTimelineEntryRow: View {
    let entry: ReportEntry
    let text: String
    let isContinuation: Bool
    let palette: ReportCardPalette

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            Text(entry.date.formatted(.dateTime.day().month(.abbreviated)))
                .font(.system(size: 17, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.muted)
                .frame(width: 86, alignment: .leading)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(isContinuation ? "Continued" : entry.clientName)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(palette.ink)
                    if !isContinuation, let project = entry.project?.trimmingCharacters(in: .whitespacesAndNewlines), !project.isEmpty {
                        Text(project)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(palette.muted)
                            .lineLimit(1)
                    }
                }
                Text(text)
                    .font(.system(size: 21))
                    .foregroundStyle(palette.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if !isContinuation {
                    HStack(spacing: 8) {
                        Label(statusTitle, systemImage: statusSymbol)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(statusColor)
                        Spacer()
                        Text(CurrencyFormatter.string(entry.amount, code: entry.currencyCode))
                            .font(.system(size: 20, weight: .semibold, design: .monospaced))
                            .foregroundStyle(palette.ink)
                    }
                }
            }
        }
    }

    private var statusTitle: String {
        switch entry.status {
        case .paid: return "Paid"
        case .inProgress: return "In progress"
        case .canceled: return "Canceled"
        }
    }

    private var statusSymbol: String {
        switch entry.status {
        case .paid: return "checkmark.circle.fill"
        case .inProgress: return "clock.fill"
        case .canceled: return "xmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch entry.status {
        case .paid: return palette.paid
        case .inProgress: return palette.progress
        case .canceled: return palette.canceled
        }
    }
}

private struct ReportTimelineNoteRow: View {
    let note: ReportEventNote
    let text: String
    let isContinuation: Bool
    let palette: ReportCardPalette

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            Text(note.date.formatted(.dateTime.day().month(.abbreviated)))
                .font(.system(size: 17, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.muted)
                .frame(width: 86, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                Label(isContinuation ? "Note continued" : "Note", systemImage: "text.quote")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.blue)
                Text(text)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct StatusCard: View {
    let title: String
    let symbol: String
    let total: ReportStatusTotal
    let color: Color
    let palette: ReportCardPalette

    var body: some View {
        ReportCardSurface(palette: palette) {
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(color)
                Text("\(total.entryCount) \(total.entryCount == 1 ? "line" : "lines")")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(palette.muted)
                Text(compactTotals(total.currencyTotals))
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .foregroundStyle(palette.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func compactTotals(_ totals: [ReportCurrencyTotal]) -> String {
        guard !totals.isEmpty else { return "—" }
        return totals.map { CurrencyFormatter.string($0.amount, code: $0.currencyCode) }.joined(separator: " · ")
    }
}

private struct CurrencyTotalsList: View {
    let totals: [ReportCurrencyTotal]
    let palette: ReportCardPalette

    var body: some View {
        if totals.isEmpty {
            Text("No included income in this period")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(palette.muted)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(totals) { total in
                    HStack {
                        Text(total.currencyCode)
                            .font(.system(size: 18, weight: .semibold, design: .monospaced))
                            .foregroundStyle(palette.muted)
                        Spacer()
                        Text(CurrencyFormatter.string(total.amount, code: total.currencyCode))
                            .font(.system(size: 28, weight: .bold).monospacedDigit())
                            .foregroundStyle(palette.ink)
                    }
                }
            }
        }
    }
}

private struct ReportCardSurface<Content: View>: View {
    let palette: ReportCardPalette
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.surface, in: .rect(cornerRadius: 30))
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(palette.hairline, lineWidth: 1)
            }
    }
}

private struct ReportHairline: View {
    let palette: ReportCardPalette

    var body: some View {
        Rectangle()
            .fill(palette.hairline)
            .frame(height: 1)
            .padding(.vertical, 3)
    }
}
