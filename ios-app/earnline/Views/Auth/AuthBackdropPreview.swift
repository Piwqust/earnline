import SwiftData
import SwiftUI

/// The live app preview behind the auth panel — the real ledger interface
/// (summary header, month divider, client chip, entry rows), not a mockup:
/// the actual components render real models from a private in-memory store,
/// and a short scripted loop makes the app demonstrate itself — a new line
/// lands in the ledger, its status flips to paid, the totals count up and
/// the sparkline morphs, then the scene resets and repeats.
///
/// Purely decorative: never hit-testable, hidden from accessibility, settled
/// to its final state under Reduce Motion or Low Power Mode, and the driving
/// task cancels automatically when the gate leaves the hierarchy.
struct AuthBackdropPreview: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var scene: BackdropScene?

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background
                .ignoresSafeArea()

            if let scene {
                BackdropSceneView(scene: scene)
                    .modelContainer(scene.container)
            }

            // Dissolve the scene into the panel so half-covered rows never
            // read as broken content.
            LinearGradient(
                colors: [Theme.background.opacity(0), Theme.background.opacity(0.85)],
                startPoint: .init(x: 0.5, y: 0.35),
                endPoint: .init(x: 0.5, y: 0.72)
            )
            .ignoresSafeArea()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: scenePhase == .background) {
            guard scenePhase != .background else { return }
            guard let scene = scene ?? (try? BackdropScene()) else { return }
            if self.scene == nil { self.scene = scene }
            if reduceMotion || ProcessInfo.processInfo.isLowPowerModeEnabled {
                scene.settle()
                return
            }
            await runLoop(scene)
        }
    }

    // MARK: Script

    private func runLoop(_ scene: BackdropScene) async {
        while !Task.isCancelled {
            withAnimation(.smooth(duration: 0.5)) { scene.resetScript() }
            try? await Task.sleep(for: .seconds(2.0))
            if Task.isCancelled { return }

            withAnimation(.smooth(duration: 0.5)) { scene.landScriptedLine() }
            try? await Task.sleep(for: .seconds(1.8))
            if Task.isCancelled { return }

            withAnimation(.snappy(duration: 0.4)) { scene.markScriptedLinePaid() }
            try? await Task.sleep(for: .seconds(3.4))
            if Task.isCancelled { return }
        }
    }
}

// MARK: - Scene view (real ledger components)

/// The exact stack the ledger renders, minus List chrome: the real
/// `LedgerSummaryHeader`, `MonthDivider`, `ClientChip`, and `EntryRow` fed by
/// the scene's models — using the ledger's own row insets. No composer here:
/// its height would push the animating rows behind the panel (and the real
/// `SmartComposer` steals keyboard focus on appear).
private struct BackdropSceneView: View {
    let scene: BackdropScene

    var body: some View {
        VStack(spacing: 0) {
            LedgerSummaryHeader(monthlyTotals: scene.monthlyTotals, onOpenStats: {})
                .padding(.top, 4)

            MonthDivider(title: DateFormat.month(.now), total: scene.currentMonthTotal)
                .padding(EdgeInsets(top: 16, leading: 16, bottom: 6, trailing: 16))

            ClientChip(
                client: scene.acme,
                total: scene.currentMonthTotal,
                onOpen: {},
                onAdd: {}
            )
            .padding(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))

            ForEach(scene.rows, id: \.id) { entry in
                EntryRow(entry: entry)
                    .padding(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
            }

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Scene model

/// A private in-memory SwiftData store holding one client's small notebook —
/// enough current-month rows to fill the visible strip and five prior months
/// of totals to draw the sparkline — plus the one scripted line the loop
/// lands, pays, and removes. Models must live in a real context: the row
/// views gate on `isInvalidated`, which reads false only for managed models.
@MainActor @Observable
final class BackdropScene {
    let container: ModelContainer
    let acme: Client
    /// Rendered current-month rows, newest first.
    private(set) var rows: [Entry]

    private let context: ModelContext
    /// Every entry that feeds the totals — rendered rows plus the prior-month
    /// seeds that exist only for the sparkline's trend.
    private var allEntries: [Entry]
    private var scriptedLine: Entry?

    init() throws {
        let schema = Schema(versionedSchema: EarnlineSchemaV2.self)
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: configuration)
        context = container.mainContext

        acme = Client(name: "Acme Studio", colorHex: "#0088FF", sortIndex: 0)
        context.insert(acme)

        let calendar = Calendar.current
        func daysAgo(_ days: Int) -> Date {
            calendar.date(byAdding: .day, value: -days, to: .now) ?? .now
        }
        func monthsAgo(_ months: Int) -> Date {
            calendar.date(byAdding: .month, value: -months, to: .now) ?? .now
        }

        let baseRows = [
            Entry(amount: 300, project: "Launch Kit", task: "Landing page",
                  date: daysAgo(3), status: .paid, sortIndex: 0),
            Entry(amount: 875, project: "Ops Console", task: "Dashboard redesign",
                  date: daysAgo(6),
                  holdUntil: calendar.date(byAdding: .day, value: 25, to: .now),
                  status: .inProgress, sortIndex: 1),
        ]
        let trendSeeds = [Decimal(420), 610, 540, 780, 820].enumerated().map { index, amount in
            Entry(amount: amount, project: "Launch Kit", task: "Earlier work",
                  date: monthsAgo(5 - index), status: .paid, sortIndex: index)
        }
        for entry in baseRows + trendSeeds {
            entry.client = acme
            context.insert(entry)
        }

        rows = baseRows
        allEntries = baseRows + trendSeeds
    }

    // MARK: Totals (the ledger's earned rule: canceled excluded)

    var monthlyTotals: [Int: Decimal] {
        var totals: [Int: Decimal] = [:]
        for entry in allEntries where !entry.isInvalidated && entry.status.isIncludedInEarnedTotals {
            totals[Insights.monthKey(of: entry.date), default: .zero] += entry.amount
        }
        return totals
    }

    var currentMonthTotal: Decimal {
        monthlyTotals[Insights.monthKey(of: .now)] ?? .zero
    }

    // MARK: Script beats

    /// A new line lands at the top of the ledger; the totals count up and the
    /// sparkline morphs because the entry immediately joins the earned sums.
    func landScriptedLine() {
        guard scriptedLine == nil else { return }
        let entry = Entry(amount: 240, project: "Launch Kit", task: "Two homepage screens",
                          date: .now, status: .inProgress, sortIndex: 2)
        entry.client = acme
        context.insert(entry)
        scriptedLine = entry
        rows.insert(entry, at: 0)
        allEntries.append(entry)
    }

    /// The landed line's status dot morphs from in-progress to paid.
    func markScriptedLinePaid() {
        scriptedLine?.status = .paid
    }

    /// Back to the resting notebook; the totals roll down with it.
    func resetScript() {
        guard let entry = scriptedLine else { return }
        scriptedLine = nil
        rows.removeAll { $0.id == entry.id }
        allEntries.removeAll { $0.id == entry.id }
        context.delete(entry)
    }

    /// Reduce Motion / Low Power: the settled end state, no loop.
    func settle() {
        landScriptedLine()
        markScriptedLinePaid()
    }
}
