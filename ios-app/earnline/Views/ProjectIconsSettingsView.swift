import SwiftData
import SwiftUI

/// Project identity stays a lightweight preference over the existing
/// free-form `Entry.project` value. This screen is opened intentionally from
/// Settings, so its entry query never adds work to the everyday settings path.
struct ProjectIconsSettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(LedgerMutationStore.self) private var mutations
    @Query(sort: \ProjectIconPreference.projectKey) private var preferences: [ProjectIconPreference]
    @State private var projects: [ProjectCatalogRow] = []
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading projects…")
            } else if projects.isEmpty {
                ContentUnavailableView(
                    "No projects yet",
                    systemImage: "folder.fill",
                    description: Text("Projects appear here after you add them to an income line.")
                )
            } else {
                List {
                    Section {
                        Text("Choose one quiet marker for each project. It appears beside the project name in your ledger.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Section("Projects") {
                        ForEach(projects) { project in
                            NavigationLink {
                                ProjectSymbolPickerView(projectName: project.name)
                            } label: {
                                ProjectCatalogLabel(
                                    projectName: project.name,
                                    symbol: assignedSymbol(for: project.name)
                                )
                            }
                            .accessibilityValue(assignedSymbol(for: project.name)?.title ?? "No icon")
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Project icons")
        .navigationBarTitleDisplayMode(.inline)
        .background(Theme.background)
        // `dataRevision`, not `ModelContext.didSave`: the notification fires for
        // every container the host keeps alive, and a sync pass saves three
        // times per pass — so this catalog reloaded on unrelated stores and
        // three times over for one pull. The revision advances once per
        // committed mutation and once per completed sync pass.
        .task(id: mutations.dataRevision) { await reloadProjects() }
        .saveErrorAlert($loadError, title: "Could not load projects")
    }

    private func assignedSymbol(for projectName: String) -> ProjectSymbol? {
        let key = ProjectIconResolver.normalizedKey(for: projectName)
        return preferences.first { $0.projectKey == key }?.symbol
    }

    @MainActor
    private func reloadProjects() async {
        isLoading = projects.isEmpty
        do {
            projects = try await ProjectCatalogLoader(modelContainer: context.container).load()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}

private struct ProjectSymbolPickerView: View {
    @Environment(AppModel.self) private var app
    @Environment(LedgerMutationStore.self) private var mutations
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(ProjectIconAppearance.userDefaultsKey) private var appearanceRaw = ProjectIconAppearance.fill.rawValue
    @Query(sort: \ProjectIconPreference.projectKey) private var preferences: [ProjectIconPreference]

    let projectName: String
    @State private var saveError: String?
    @State private var previewEntry: Entry
    @State private var selectionFeedback = 0

    init(projectName: String) {
        self.projectName = projectName
        _previewEntry = State(initialValue: Entry(
            amount: 390,
            project: projectName,
            task: String(localized: "New income line"),
            status: .paid
        ))
    }

    private var columns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 4 : 6
        return Array(repeating: GridItem(.flexible(), spacing: 8), count: count)
    }

    private var selection: ProjectSymbol {
        ProjectIconResolver.symbol(for: projectName, in: preferences)
    }

    private var appearance: ProjectIconAppearance {
        ProjectIconAppearance(rawValue: appearanceRaw) ?? .fill
    }

    private var appearanceBinding: Binding<ProjectIconAppearance> {
        Binding(
            get: { appearance },
            set: { appearanceRaw = $0.rawValue }
        )
    }

    private var appearanceTitle: String {
        appearance == .outline ? String(localized: "Outline") : String(localized: "Fill")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ledgerPreview
                appearancePicker
                iconLibrary
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 28)
        }
        .navigationTitle("Project icon")
        .navigationBarTitleDisplayMode(.inline)
        .background(Theme.background)
        .sensoryFeedback(.selection, trigger: selectionFeedback)
        .saveErrorAlert($saveError, title: "Could not save project icon")
    }

    private var ledgerPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Preview")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            // This is the production ledger renderer. The transient entry is
            // never inserted into SwiftData, so selecting a symbol cannot
            // create or modify income data.
            EntryRow(entry: previewEntry,
                     projectSymbol: selection,
                     rendersTransientEntry: true)
                .allowsHitTesting(false)
        }
        .padding(16)
        .background(Theme.surface, in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(Theme.hairline, lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview")
        .accessibilityIdentifier("projectIcon.preview")
        .accessibilityValue("\(selection.title), \(appearanceTitle)")
        .onAppear { previewEntry.currencyCode = app.baseCurrencyCode }
    }

    private var appearancePicker: some View {
        HStack(spacing: 12) {
            Text("Symbol style")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            Picker("Symbol style", selection: appearanceBinding) {
                Text("Outline").tag(ProjectIconAppearance.outline)
                Text("Fill").tag(ProjectIconAppearance.fill)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 164, height: 44)
            .accessibilityIdentifier("projectIcon.appearance")
        }
    }

    private var iconLibrary: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Choose an icon")
                .font(.headline)
                .foregroundStyle(Theme.label)

            ForEach(ProjectSymbolCategory.allCases) { category in
                VStack(alignment: .leading, spacing: 12) {
                    Text(category.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .accessibilityIdentifier("projectIcon.category.\(category.id)")

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(category.symbols) { symbol in
                            symbolButton(symbol)
                        }
                    }
                }
            }
        }
    }

    private func symbolButton(_ symbol: ProjectSymbol) -> some View {
        let isSelected = selection == symbol
        return Button {
            select(symbol)
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: symbol.systemImageName(for: appearance))
                    .font(.title3.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? app.accentColor : Theme.label)
                    .symbolEffect(.bounce, options: .nonRepeating,
                                  value: reduceMotion ? 0 : selectionFeedback)
                    .symbolEffectsRemoved(reduceMotion)
                    .frame(width: 52, height: 52)
                    .background(
                        isSelected ? app.accentColor.opacity(0.14) : Color(uiColor: .tertiarySystemFill),
                        in: .circle
                    )
                    .overlay {
                        Circle()
                            .stroke(isSelected ? app.accentColor.opacity(0.55) : .clear,
                                    lineWidth: 1)
                    }

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(app.accentColor, in: .circle)
                        .offset(x: 2, y: -2)
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .snappy(duration: 0.26, extraBounce: 0.12),
                   value: isSelected)
        .accessibilityLabel(symbol.title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("projectIcon.option.\(symbol.id)")
    }

    private func select(_ symbol: ProjectSymbol) {
        guard symbol != selection else { return }
        do {
            try ProjectIconPreferenceStore.set(symbol, for: projectName, in: context)
            saveError = mutations.save(context)
            if saveError == nil { selectionFeedback += 1 }
        } catch {
            saveError = error.localizedDescription
        }
    }
}

private struct ProjectCatalogLabel: View {
    let projectName: String
    let symbol: ProjectSymbol?
    @AppStorage(ProjectIconAppearance.userDefaultsKey) private var appearanceRaw = ProjectIconAppearance.fill.rawValue

    private var appearance: ProjectIconAppearance {
        ProjectIconAppearance(rawValue: appearanceRaw) ?? .fill
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol?.systemImageName(for: appearance)
                  ?? ProjectSymbol.folder.systemImageName(for: appearance))
                .font(.body.weight(.medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(symbol == nil ? .tertiary : .secondary)
                .frame(width: 24, height: 28)
                .accessibilityHidden(true)

            Text(projectName)
                .foregroundStyle(Theme.label)
                .lineLimit(2)

            Spacer(minLength: 8)

            Text(symbol?.title ?? "Choose")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private struct ProjectCatalogRow: Identifiable, Sendable {
    let id: String
    let name: String
}

/// Distinct-project discovery walks the ledger off the main actor. Opening the
/// picker therefore stays responsive even with a multi-thousand-line ledger.
@ModelActor
private actor ProjectCatalogLoader {
    func load() throws -> [ProjectCatalogRow] {
        let entries = try modelContext.fetch(FetchDescriptor<Entry>(
            sortBy: [SortDescriptor(\Entry.updatedAt, order: .reverse)]
        ))
        var namesByKey: [String: String] = [:]
        for entry in entries {
            guard let name = entry.project?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else { continue }
            let key = ProjectIconResolver.normalizedKey(for: name)
            if namesByKey[key] == nil { namesByKey[key] = name }
        }
        return namesByKey.map { ProjectCatalogRow(id: $0.key, name: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

extension ProjectSymbol {
    var title: String {
        switch self {
        case .folder: return String(localized: "Folder")
        case .briefcase: return String(localized: "Work")
        case .display: return String(localized: "Digital")
        case .paintpalette: return String(localized: "Design")
        case .camera: return String(localized: "Photo")
        case .video: return String(localized: "Video")
        case .music: return String(localized: "Music")
        case .document: return String(localized: "Document")
        case .megaphone: return String(localized: "Campaign")
        case .cart: return String(localized: "Commerce")
        case .globe: return String(localized: "Web")
        case .tools: return String(localized: "Tools")
        case .package: return String(localized: "Product")
        case .sparkles: return String(localized: "Creative")
        case .chart: return String(localized: "Growth")
        case .building: return String(localized: "Business")
        case .app: return String(localized: "App")
        case .cloud: return String(localized: "Cloud")
        case .terminal: return String(localized: "Code")
        case .bolt: return String(localized: "Fast")
        case .cpu: return String(localized: "Technology")
        case .photo: return String(localized: "Image")
        case .pencil: return String(localized: "Writing")
        case .theater: return String(localized: "Studio")
        case .creditCard: return String(localized: "Card")
        case .banknote: return String(localized: "Money")
        case .people: return String(localized: "Team")
        case .calendar: return String(localized: "Schedule")
        case .storefront: return String(localized: "Store")
        case .bag: return String(localized: "Shopping")
        case .book: return String(localized: "Book")
        case .graduationCap: return String(localized: "Learning")
        case .lightbulb: return String(localized: "Idea")
        case .target: return String(localized: "Goal")
        case .paintbrush: return String(localized: "Art")
        case .wand: return String(localized: "Magic")
        case .microphone: return String(localized: "Audio")
        case .headphones: return String(localized: "Sound")
        case .keyboard: return String(localized: "Keyboard")
        case .server: return String(localized: "Server")
        case .network: return String(localized: "Network")
        case .gear: return String(localized: "System")
        case .tag: return String(localized: "Tag")
        case .receipt: return String(localized: "Invoice")
        case .phone: return String(localized: "Phone")
        case .envelope: return String(localized: "Email")
        case .collaborate: return String(localized: "Collaboration")
        case .location: return String(localized: "Location")
        }
    }
}

private enum ProjectSymbolCategory: String, CaseIterable, Identifiable {
    case work
    case creative
    case digital
    case commerce

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .work: "Work"
        case .creative: "Creative"
        case .digital: "Digital"
        case .commerce: "Commerce"
        }
    }

    var symbols: [ProjectSymbol] {
        switch self {
        case .work:
            [.folder, .briefcase, .document, .package, .building, .tools, .chart, .people,
             .book, .graduationCap, .lightbulb, .target]
        case .creative:
            [.paintpalette, .sparkles, .camera, .video, .photo, .music, .pencil, .theater,
             .paintbrush, .wand, .microphone, .headphones]
        case .digital:
            [.display, .app, .cloud, .terminal, .bolt, .cpu, .globe, .calendar,
             .keyboard, .server, .network, .gear]
        case .commerce:
            [.cart, .creditCard, .banknote, .megaphone, .storefront, .bag,
             .tag, .receipt, .phone, .envelope, .collaborate, .location]
        }
    }
}
