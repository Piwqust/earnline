import SwiftData
import SwiftUI

/// The live app story behind the account dock. It uses a transient in-memory
/// store and production SwiftUI surfaces — never a video, screenshot, or
/// duplicate card system. The surface is decorative and cannot receive input
/// or VoiceOver focus.
struct AuthBackdropPreview: View {
    @Environment(\.accessibilityPlayAnimatedImages) private var playAnimatedImages
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    let isActive: Bool
    let dockHeight: CGFloat

    @State private var director: AuthTourDirector?
    @State private var lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

    private struct PlaybackKey: Hashable {
        let isActive: Bool
        let scenePhase: ScenePhase
        let reduceMotion: Bool
        let playAnimatedImages: Bool
        let lowPowerMode: Bool
    }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background
                .ignoresSafeArea()

            if let director {
                AuthTourStage(
                    scene: director.scene,
                    dockHeight: dockHeight
                )
                .modelContainer(director.scene.container)
            }

            // The dock needs contrast, but it should not erase the establishing
            // shot. The modest lower falloff lets the ledger stay readable.
            LinearGradient(
                colors: [Theme.background.opacity(0), Theme.background.opacity(0.28)],
                startPoint: .init(x: 0.5, y: 0.56),
                endPoint: .init(x: 0.5, y: 0.92)
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: PlaybackKey(
            isActive: isActive,
            scenePhase: scenePhase,
            reduceMotion: reduceMotion,
            playAnimatedImages: playAnimatedImages,
            lowPowerMode: lowPowerMode
        )) {
            let director = director ?? (try? AuthTourDirector())
            guard let director else { return }
            if self.director == nil { self.director = director }

            director.configure(
                options: AuthTourPreviewOptions.launchOptions,
                policy: AuthTourPlaybackPolicy.resolve(
                    isAccountDockActive: isActive,
                    scenePhase: scenePhase,
                    reduceMotion: reduceMotion,
                    playAnimatedImages: playAnimatedImages,
                    lowPowerMode: lowPowerMode
                )
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }
}

// MARK: - Tour direction

/// Semantic states of the story. The director owns these states and its seeded
/// data; rendering owns one directional replacement between them.
enum AuthTourBeat: String, CaseIterable, Hashable {
    case ledger
    case addIncome
    case edit
    case insights
    case client

}

/// Test-only launch controls. Production never supplies these values; they
/// exist so UI screenshots and director tests can land on a repeatable beat.
struct AuthTourPreviewOptions: Hashable {
    var forcedBeat: AuthTourBeat?
    var prefersStaticPlayback = false

    static var launchOptions: Self {
        guard AppModel.isRunningUIAutomation else { return .init() }
        let arguments = ProcessInfo.processInfo.arguments
        let requestedBeat = argumentValue("-authTourBeat", in: arguments)
            .flatMap(AuthTourBeat.init(rawValue:))
            ?? legacyScreenBeat(argumentValue("-authPreviewScreen", in: arguments))
        return .init(
            forcedBeat: requestedBeat,
            prefersStaticPlayback: arguments.contains("-authTourStatic")
        )
    }

    private static func argumentValue(_ name: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    private static func legacyScreenBeat(_ value: String?) -> AuthTourBeat? {
        switch value {
        case "ledger": .ledger
        case "editor": .edit
        case "insights": .insights
        case "client": .client
        default: nil
        }
    }
}

enum AuthTourPlaybackPolicy: Hashable {
    case autoplay
    case settled

    static func resolve(
        isAccountDockActive: Bool,
        scenePhase: ScenePhase,
        reduceMotion: Bool,
        playAnimatedImages: Bool,
        lowPowerMode: Bool
    ) -> Self {
        guard isAccountDockActive,
              scenePhase == .active,
              !reduceMotion,
              playAnimatedImages,
              !lowPowerMode else {
            return .settled
        }
        return .autoplay
    }
}

/// One timing vocabulary for the tour. Keeping every visual handoff here
/// makes the loop read as a calm sequence, rather than unrelated components
/// competing with their own animation clocks.
enum AuthTourTiming {
    static let beatMorph: TimeInterval = 0.52
    static let lineMorph: TimeInterval = 0.46
    static let editorStatus: TimeInterval = 0.44
    static let chartReveal: TimeInterval = 1.18
    static let clientContentFade: TimeInterval = 0.46

    static let establishingDwell: TimeInterval = 1.6
    static let composerDwell: TimeInterval = 2.6
    static let editorBeforePayment: TimeInterval = 0.75
    static let editorAfterPayment: TimeInterval = 1.75
    static let chartBeforeReveal: TimeInterval = 0.55
    static let chartAfterReveal: TimeInterval = 2.2
    static let clientBeforeHistory: TimeInterval = 0.7
    static let clientAfterHistory: TimeInterval = 2.0
    static let resetDwell: TimeInterval = 1.1
}

/// Every tour replacement shares one stable spatial rule: the outgoing
/// surface leaves above the stage and the next one enters from below it. This
/// reads as a contained native sheet-like morph, without camera transforms or
/// transparent crossfades.
private enum AuthTourTransition {
    static var fromBottom: AnyTransition {
        .asymmetric(
            insertion: .push(from: .bottom),
            removal: .push(from: .top)
        )
    }
}

/// The director's only clock dependency. The production sleeper waits in real
/// time; tests inject a recording or immediate sleeper to assert ordering,
/// reset, pause, and resume without sleeping for a ten-second loop.
protocol AuthTourSleeping: Sendable {
    func sleep(for duration: Duration) async throws
}

struct SystemAuthTourSleeper: AuthTourSleeping {
    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

@MainActor @Observable
final class AuthTourDirector {
    let scene: AuthTourScene
    private let sleeper: any AuthTourSleeping

    private(set) var beat: AuthTourBeat = .ledger
    private(set) var playbackPolicy: AuthTourPlaybackPolicy = .settled
    private(set) var beatHistory: [AuthTourBeat] = []
    private var playbackTask: Task<Void, Never>?

    init(scene: AuthTourScene? = nil, sleeper: any AuthTourSleeping = SystemAuthTourSleeper()) throws {
        self.scene = try scene ?? AuthTourScene()
        self.sleeper = sleeper
    }

    func configure(options: AuthTourPreviewOptions, policy: AuthTourPlaybackPolicy) {
        playbackTask?.cancel()
        playbackPolicy = options.prefersStaticPlayback ? .settled : policy

        if let forcedBeat = options.forcedBeat {
            playbackPolicy = .settled
            move(to: forcedBeat)
            scene.completeStaticPreview(for: forcedBeat)
            return
        }

        guard playbackPolicy == .autoplay else {
            settle()
            return
        }

        playbackTask = Task { [weak self] in
            await self?.playLoop()
        }
    }

    func pause() {
        playbackTask?.cancel()
        playbackTask = nil
        playbackPolicy = .settled
        settle()
    }

    func move(to beat: AuthTourBeat) {
        self.beat = beat
        beatHistory.append(beat)
        scene.prepare(for: beat)
    }

    private func settle() {
        beat = .ledger
        scene.settle()
    }

    private func playLoop() async {
        while !Task.isCancelled {
            guard await playOneCycle() else { return }
        }
    }

    /// Kept internal for deterministic unit tests with an injected sleeper.
    /// Production only enters this through the looping task above.
    func playOneCycleForTesting() async -> Bool {
        await playOneCycle()
    }

    private func playOneCycle() async -> Bool {
        // One short connected story, not a feature carousel. Each state is
        // long enough to read once, and the same income line is the visual
        // thread from draft to client history.
        move(to: .ledger)
        guard await pause(for: AuthTourTiming.establishingDwell) else { return false }

        move(to: .addIncome)
        guard await pause(for: AuthTourTiming.composerDwell) else { return false }

        move(to: .edit)
        guard await pause(for: AuthTourTiming.editorBeforePayment) else { return false }
        scene.markIncomePaid()
        guard await pause(for: AuthTourTiming.editorAfterPayment) else { return false }

        move(to: .insights)
        guard await pause(for: AuthTourTiming.chartBeforeReveal) else { return false }
        scene.revealInsightsChart()
        guard await pause(for: AuthTourTiming.chartAfterReveal) else { return false }

        move(to: .client)
        guard await pause(for: AuthTourTiming.clientBeforeHistory) else { return false }
        scene.revealClientHistory()
        guard await pause(for: AuthTourTiming.clientAfterHistory) else { return false }

        move(to: .ledger)
        return await pause(for: AuthTourTiming.resetDwell)
    }

    private func pause(for seconds: Double) async -> Bool {
        do {
            try await sleeper.sleep(for: .seconds(seconds))
        } catch {
            return false
        }
        return !Task.isCancelled
    }
}

private struct AuthTourStage: View {
    let scene: AuthTourScene
    let dockHeight: CGFloat

    var body: some View {
        GeometryReader { proxy in
            // Make the amount of visible app intentional rather than assuming
            // a fixed panel height. The extra headroom keeps a full ledger
            // readable above a taller localized dock.
            let readableHeight = max(280, proxy.size.height - dockHeight + 24)

            AuthPreviewScreen(scene: scene)
                .frame(width: proxy.size.width, height: readableHeight + 112, alignment: .top)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .clipped()
    }
}

// MARK: - Real app screens

private struct AuthPreviewScreen: View {
    @Environment(AppModel.self) private var app
    let scene: AuthTourScene

    var body: some View {
        // The ledger remains the anchor. A beat replaces it directionally;
        // no second animation system may move, zoom, or rotate this surface.
        ZStack(alignment: .top) {
            ledger

            switch scene.screen {
            case .ledger:
                EmptyView()
            case .editor:
                editor
                    .transition(AuthTourTransition.fromBottom)
            case .insights:
                focusedSurface { insights }
                    .transition(AuthTourTransition.fromBottom)
            case .client:
                focusedSurface { client }
                    .transition(AuthTourTransition.fromBottom)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.background)
        .animation(.smooth(duration: AuthTourTiming.beatMorph, extraBounce: 0), value: scene.screen)
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

            storyLine
                .padding(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))

            ForEach(rowsBelowStoryLine, id: \.id) { entry in
                EntryRow(entry: entry)
                    .padding(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }

            Spacer(minLength: 0)
        }
    }

    /// The draft composer resolves into its saved row. It is a directional
    /// replacement, not a crossfade: the composer clears upward and the row
    /// arrives from below, using one axis and one animation transaction.
    private var storyLine: some View {
        Group {
            if scene.showsComposer {
                SmartComposer(
                    client: scene.acme,
                    initialText: "$240 Launch Kit: Two homepage screens",
                    automaticallyFocus: false
                )
                .transition(AuthTourTransition.fromBottom)
            }

            if let entry = scene.scriptedLine, !scene.showsComposer {
                EntryRow(entry: entry)
                    .transition(AuthTourTransition.fromBottom)
            }
        }
        .animation(.smooth(duration: AuthTourTiming.lineMorph, extraBounce: 0), value: scene.showsComposer)
    }

    private var rowsBelowStoryLine: [Entry] {
        scene.rows.filter { $0.id != scene.scriptedLine?.id }
    }

    /// Insights and client detail need a full, opaque canvas while they cross
    /// the stage. Keeping that canvas in the same transition prevents the
    /// ledger from ghosting through their arrival.
    private func focusedSurface<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        Theme.background
            .overlay(alignment: .top) { content() }
    }

    @ViewBuilder
    private var editor: some View {
        if let entry = scene.scriptedLine {
            NavigationStack {
                EditEntrySheet(
                    entry: entry,
                    clients: [scene.acme],
                    previewStatus: scene.editorStatus,
                    previewStatusAnimationDuration: AuthTourTiming.editorStatus,
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

    /// This is the production chart card, shown at the moment the newly paid
    /// line becomes a visible monthly trend. It deliberately has no new
    /// dashboard shell or mock metric cards around it.
    private var insights: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Monthly income")
                .appFont(13, .semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)

            EarningsChartCard(
                points: scene.monthlyTrendPoints,
                tint: app.accentColor,
                window: nil,
                drawProgress: scene.insightsChartProgress,
                previewDrawDuration: AuthTourTiming.chartReveal
            )
            .padding(.horizontal, 16)
        }
        .padding(.top, 22)
    }

    /// The actual client profile is retained as the final meaning-making
    /// moment: the income line belongs to a person and a relationship, not
    /// merely a total. Without a navigation stack it reads as an in-canvas
    /// close-up rather than another app launch.
    private var client: some View {
        ClientDetailView(
            client: scene.acme,
            previewHistoryIsLoaded: scene.clientHistoryLoaded,
            previewHistoryTransitionDuration: AuthTourTiming.clientContentFade
        )
        .padding(.top, 2)
    }
}

// MARK: - In-memory story data

@MainActor @Observable
final class AuthTourScene {
    enum Screen: Hashable {
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
    private(set) var insightsChartProgress: CGFloat = 1
    private(set) var clientHistoryLoaded = true

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

    var monthlyTrendPoints: [EarningsChartCard.Point] {
        let calendar = Calendar.current
        let months = (0..<6).reversed().compactMap {
            calendar.date(byAdding: .month, value: -$0, to: .now)
        }
        var previousTotal: Decimal?

        return months.map { month in
            let total = allEntries
                .filter {
                    !($0.isInvalidated)
                        && $0.status.isIncludedInEarnedTotals
                        && calendar.isDate($0.date, equalTo: month, toGranularity: .month)
                }
                .reduce(Decimal.zero) { $0 + $1.amount }
            defer { previousTotal = total }
            return EarningsChartCard.Point(
                month: month,
                total: total,
                previousTotal: previousTotal
            )
        }
    }

    func prepare(for beat: AuthTourBeat) {
        switch beat {
        case .ledger:
            reset()
        case .addIncome:
            addIncomeLine()
        case .edit:
            openEditor()
        case .insights:
            openInsights()
        case .client:
            openClientProfile()
        }
    }

    /// UI-test captures represent the readable end of each beat, not the
    /// first frame of its reveal animation.
    func completeStaticPreview(for beat: AuthTourBeat) {
        switch beat {
        case .insights:
            revealInsightsChart()
        case .client:
            revealClientHistory()
        case .ledger, .addIncome, .edit:
            break
        }
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
        insightsChartProgress = 1
        clientHistoryLoaded = true
    }

    func addIncomeLine() {
        guard scriptedLine == nil else {
            screen = .ledger
            return
        }
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
        // A forced test beat can enter the editor after the settled ledger,
        // whose row is paid. Restore the editor's scripted starting state.
        editorStatus = .inProgress
        scriptedLine?.status = .inProgress
        screen = .editor
    }

    func markIncomePaid() {
        editorStatus = .paid
        scriptedLine?.status = .paid
    }

    func openInsights() {
        markIncomePaid()
        screen = .insights
        insightsChartProgress = 0
    }

    func revealInsightsChart() {
        insightsChartProgress = 1
    }

    func openClientProfile() {
        markIncomePaid()
        screen = .client
        clientHistoryLoaded = false
    }

    func revealClientHistory() {
        clientHistoryLoaded = true
    }

    func settle() {
        if scriptedLine == nil { addIncomeLine() }
        markIncomePaid()
        screen = .ledger
        showsComposer = false
        insightsChartProgress = 1
        clientHistoryLoaded = true
    }
}
