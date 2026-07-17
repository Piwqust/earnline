import SwiftData
import SwiftUI

/// The live app story behind the account panel. It renders the production
/// ledger, composer, editor, Insights, and client-profile components against a
/// short-lived in-memory store — never a screenshot or a second UI system.
///
/// The surface is decorative: it cannot receive input or VoiceOver focus. It
/// stops on a calm, completed ledger when motion should not autoplay.
struct AuthBackdropPreview: View {
    @Environment(\.accessibilityPlayAnimatedImages) private var playAnimatedImages
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    let isActive: Bool

    @State private var scene: AuthPreviewScene?
    @State private var lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

    private struct PlaybackKey: Hashable {
        let isActive: Bool
        let isBackgrounded: Bool
        let reduceMotion: Bool
        let playAnimatedImages: Bool
        let lowPowerMode: Bool
    }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background
                .ignoresSafeArea()

            if let scene {
                AuthPreviewScreen(scene: scene)
                    .modelContainer(scene.container)
                    .id(scene.screen)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            // The panel needs a little separation, but the app should remain
            // recognisable well behind it instead of dissolving halfway down.
            LinearGradient(
                colors: [Theme.background.opacity(0), Theme.background.opacity(0.35)],
                startPoint: .init(x: 0.5, y: 0.52),
                endPoint: .init(x: 0.5, y: 0.9)
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: PlaybackKey(
            isActive: isActive,
            isBackgrounded: scenePhase == .background,
            reduceMotion: reduceMotion,
            playAnimatedImages: playAnimatedImages,
            lowPowerMode: lowPowerMode
        )) {
            guard let scene = scene ?? (try? AuthPreviewScene()) else { return }
            if self.scene == nil { self.scene = scene }

            if let requestedScreen {
                scene.prepareForPreview(requestedScreen)
                return
            }

            guard scenePhase != .background, isActive else { return }
            guard !reduceMotion,
                  playAnimatedImages,
                  !lowPowerMode else {
                scene.settle()
                return
            }
            await runLoop(scene)
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }

    private var requestedScreen: AuthPreviewScene.Screen? {
        guard AppModel.isRunningUIAutomation else { return nil }
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-authPreviewScreen"),
              arguments.indices.contains(index + 1) else { return nil }
        return AuthPreviewScene.Screen(rawValue: arguments[index + 1])
    }

    private func runLoop(_ scene: AuthPreviewScene) async {
        while !Task.isCancelled {
            withAnimation(.smooth(duration: 0.45)) { scene.reset() }
            guard await wait(1.2) else { return }

            withAnimation(.smooth(duration: 0.5)) { scene.addIncomeLine() }
            guard await wait(1.5) else { return }

            withAnimation(.smooth(duration: 0.45)) { scene.openEditor() }
            guard await wait(1.4) else { return }

            withAnimation(.snappy(duration: 0.35)) { scene.markIncomePaid() }
            guard await wait(1.0) else { return }

            withAnimation(.smooth(duration: 0.55)) { scene.openInsights() }
            guard await wait(2.4) else { return }

            withAnimation(.smooth(duration: 0.55)) { scene.openClientProfile() }
            guard await wait(2.4) else { return }
        }
    }

    private func wait(_ seconds: Double) async -> Bool {
        do {
            try await Task.sleep(for: .seconds(seconds))
        } catch {
            return false
        }
        return !Task.isCancelled
    }
}

// MARK: - Real app screens

private struct AuthPreviewScreen: View {
    let scene: AuthPreviewScene

    var body: some View {
        Group {
            switch scene.screen {
            case .ledger:
                ledger
            case .editor:
                editor
            case .insights:
                NavigationStack { InsightsView() }
            case .client:
                NavigationStack { ClientDetailView(client: scene.acme) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.background)
    }

    private var ledger: some View {
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

            if scene.showsComposer {
                SmartComposer(
                    client: scene.acme,
                    initialText: "$240 Launch Kit: Two homepage screens",
                    automaticallyFocus: false
                )
                .padding(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .transition(.move(edge: .top).combined(with: .opacity))
            }

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

    @ViewBuilder
    private var editor: some View {
        if let entry = scene.scriptedLine {
            NavigationStack {
                EditEntrySheet(
                    entry: entry,
                    clients: [scene.acme],
                    previewStatus: scene.editorStatus,
                    previewValues: .init(
                        amount: 240,
                        currencyCode: "USD",
                        project: "Launch Kit",
                        task: "Two homepage screens",
                        status: .inProgress
                    )
                )
            }
        } else {
            ledger
        }
    }
}

// MARK: - In-memory story

@MainActor @Observable
final class AuthPreviewScene {
    enum Screen: String, Hashable {
        case ledger
        case editor
        case insights
        case client
    }

    let container: ModelContainer
    let acme: Client
    private(set) var rows: [Entry]
    private(set) var screen: Screen = .ledger
    private(set) var showsComposer = true
    private(set) var scriptedLine: Entry?
    private(set) var editorStatus: EntryStatus = .inProgress

    private let context: ModelContext
    private var allEntries: [Entry]

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

    func reset() {
        if let entry = scriptedLine {
            rows.removeAll { $0.id == entry.id }
            allEntries.removeAll { $0.id == entry.id }
            context.delete(entry)
        }
        scriptedLine = nil
        screen = .ledger
        showsComposer = true
        editorStatus = .inProgress
    }

    func addIncomeLine() {
        guard scriptedLine == nil else { return }
        let entry = Entry(amount: 240, project: "Launch Kit", task: "Two homepage screens",
                          date: .now, status: .inProgress, sortIndex: -1)
        entry.client = acme
        context.insert(entry)
        scriptedLine = entry
        rows.insert(entry, at: 0)
        allEntries.append(entry)
        screen = .ledger
        showsComposer = false
        editorStatus = .inProgress
    }

    func openEditor() {
        addIncomeLine()
        screen = .editor
    }

    func markIncomePaid() {
        editorStatus = .paid
        scriptedLine?.status = .paid
    }

    func openInsights() {
        markIncomePaid()
        screen = .insights
    }

    func openClientProfile() {
        markIncomePaid()
        screen = .client
    }

    func settle() {
        screen = .ledger
        showsComposer = false
        editorStatus = .paid
    }

    func prepareForPreview(_ requestedScreen: Screen) {
        reset()
        switch requestedScreen {
        case .ledger:
            break
        case .editor:
            openEditor()
        case .insights:
            addIncomeLine()
            openInsights()
        case .client:
            addIncomeLine()
            openClientProfile()
        }
    }
}
