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
                    shouldAnimate: director.playbackPolicy == .autoplay,
                    staticCamera: director.beat.camera,
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
/// data; the camera animator only reads transform values and never mutates a
/// SwiftData model inside a per-frame closure.
enum AuthTourBeat: String, CaseIterable, Hashable {
    case ledger
    case addIncome
    case edit
    case insights
    case client

    var camera: AuthTourCamera {
        switch self {
        case .ledger: .wide
        case .addIncome: .composer
        case .edit: .editor
        case .insights: .insights
        case .client: .client
        }
    }
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
        guard await pause(for: 0.8) else { return false }

        move(to: .addIncome)
        guard await pause(for: 1.5) else { return false }

        move(to: .edit)
        guard await pause(for: 0.45) else { return false }
        scene.markIncomePaid()
        guard await pause(for: 0.85) else { return false }

        move(to: .insights)
        guard await pause(for: 0.18) else { return false }
        scene.revealInsightsChart()
        guard await pause(for: 1.62) else { return false }

        move(to: .client)
        guard await pause(for: 0.18) else { return false }
        scene.revealClientHistory()
        guard await pause(for: 1.22) else { return false }

        move(to: .ledger)
        return await pause(for: 0.6)
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

// MARK: - Camera

/// A camera transform contains visual values only. It is intentionally plain
/// data so `KeyframeAnimator` can interpolate it without any model queries.
struct AuthTourCamera {
    var scale: CGFloat
    var x: CGFloat
    var y: CGFloat
    var yaw: Double
    var opacity: Double

    static let wide = Self(scale: 0.98, x: 0, y: 0, yaw: 0, opacity: 1)
    static let composer = Self(scale: 0.99, x: 0, y: -16, yaw: 0, opacity: 1)
    static let editor = Self(scale: 0.96, x: 8, y: -24, yaw: 0.6, opacity: 1)
    static let insights = Self(scale: 0.99, x: 0, y: 0, yaw: 0, opacity: 1)
    static let client = Self(scale: 0.98, x: -8, y: 0, yaw: -0.5, opacity: 1)
}

private struct AuthTourStage: View {
    let scene: AuthTourScene
    let shouldAnimate: Bool
    let staticCamera: AuthTourCamera
    let dockHeight: CGFloat

    var body: some View {
        GeometryReader { proxy in
            // Make the amount of visible app intentional rather than assuming
            // a fixed panel height. The extra headroom keeps a full ledger
            // readable above a taller localized dock.
            let readableHeight = max(280, proxy.size.height - dockHeight + 24)

            if shouldAnimate {
                AuthTourAnimatedScreen(
                    scene: scene,
                    size: proxy.size,
                    readableHeight: readableHeight
                )
            } else {
                AuthPreviewScreen(scene: scene)
                    .frame(width: proxy.size.width, height: readableHeight + 112, alignment: .top)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                    .authTourCamera(staticCamera)
            }
        }
        .clipped()
    }
}

/// One repeating 7.4-second transform timeline. The content closure applies
/// only scale, offset, perspective, and opacity; semantic beat changes happen
/// in `AuthTourDirector`, outside this per-frame work.
private struct AuthTourAnimatedScreen: View {
    let scene: AuthTourScene
    let size: CGSize
    let readableHeight: CGFloat

    var body: some View {
        AuthPreviewScreen(scene: scene)
            .frame(width: size.width, height: readableHeight + 112, alignment: .top)
            .frame(width: size.width, height: size.height, alignment: .top)
            .keyframeAnimator(
            initialValue: AuthTourCamera.wide,
            repeating: true
        ) { content, camera in
            content.authTourCamera(camera)
        } keyframes: { _ in
            KeyframeTrack(\.scale) {
                LinearKeyframe(0.98, duration: 0.8)
                CubicKeyframe(0.99, duration: 0.4)
                LinearKeyframe(0.99, duration: 1.1)
                CubicKeyframe(0.96, duration: 0.25)
                LinearKeyframe(0.96, duration: 1.05)
                CubicKeyframe(0.99, duration: 0.3)
                LinearKeyframe(0.99, duration: 1.5)
                CubicKeyframe(0.98, duration: 0.25)
                LinearKeyframe(0.98, duration: 1.15)
                CubicKeyframe(0.98, duration: 0.25)
                LinearKeyframe(0.98, duration: 0.35)
            }
            KeyframeTrack(\.x) {
                LinearKeyframe(0, duration: 2.3)
                CubicKeyframe(8, duration: 0.25)
                LinearKeyframe(8, duration: 1.05)
                CubicKeyframe(0, duration: 0.3)
                LinearKeyframe(0, duration: 1.5)
                CubicKeyframe(-8, duration: 0.25)
                LinearKeyframe(-8, duration: 1.15)
                CubicKeyframe(0, duration: 0.25)
                LinearKeyframe(0, duration: 0.35)
            }
            KeyframeTrack(\.y) {
                LinearKeyframe(0, duration: 0.8)
                CubicKeyframe(-16, duration: 0.4)
                LinearKeyframe(-16, duration: 1.1)
                CubicKeyframe(-24, duration: 0.25)
                LinearKeyframe(-24, duration: 1.05)
                CubicKeyframe(0, duration: 0.3)
                LinearKeyframe(0, duration: 1.5)
                LinearKeyframe(0, duration: 1.4)
                LinearKeyframe(0, duration: 0.6)
            }
            KeyframeTrack(\.yaw) {
                LinearKeyframe(0, duration: 2.3)
                CubicKeyframe(0.6, duration: 0.25)
                LinearKeyframe(0.6, duration: 1.05)
                CubicKeyframe(0, duration: 0.3)
                LinearKeyframe(0, duration: 1.5)
                CubicKeyframe(-0.5, duration: 0.25)
                LinearKeyframe(-0.5, duration: 1.15)
                CubicKeyframe(0, duration: 0.25)
                LinearKeyframe(0, duration: 0.35)
            }
            KeyframeTrack(\.opacity) {
                LinearKeyframe(1, duration: 6.8)
                CubicKeyframe(0.94, duration: 0.2)
                CubicKeyframe(1, duration: 0.4)
            }
        }
    }
}

private extension View {
    nonisolated func authTourCamera(_ camera: AuthTourCamera) -> some View {
        scaleEffect(camera.scale, anchor: .top)
            .rotation3DEffect(
                .degrees(camera.yaw),
                axis: (x: 0, y: 1, z: 0),
                anchor: .center,
                perspective: 0.72
            )
            .offset(x: camera.x, y: camera.y)
            .opacity(camera.opacity)
    }
}

// MARK: - Real app screens

private struct AuthPreviewScreen: View {
    @Environment(AppModel.self) private var app
    let scene: AuthTourScene
    @Namespace private var incomeTransition

    var body: some View {
        // Keep the ledger on stage for the whole story. The focused surfaces
        // arrive as a consequence of the same line of income instead of
        // replacing the scene with a disconnected feature slide.
        ZStack(alignment: .top) {
            ledger
                .opacity(scene.screen == .ledger ? 1 : 0.14)
                .scaleEffect(scene.screen == .ledger ? 1 : 0.975, anchor: .top)

            switch scene.screen {
            case .ledger:
                EmptyView()
            case .editor:
                editor
                    .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))
            case .insights:
                insights
                    .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))
            case .client:
                client
                    .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.background)
        .animation(.smooth(duration: 0.32), value: scene.screen)
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
                .matchedGeometryEffect(id: "tour.income", in: incomeTransition, isSource: true)
                .padding(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            ForEach(scene.rows, id: \.id) { entry in
                EntryRow(entry: entry)
                    .matchedGeometryEffect(
                        id: entry.id == scene.scriptedLine?.id ? "tour.income" : entry.id.uuidString,
                        in: incomeTransition,
                        isSource: entry.id == scene.scriptedLine?.id
                    )
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
                drawProgress: scene.insightsChartProgress
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
            previewHistoryIsLoaded: scene.clientHistoryLoaded
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
