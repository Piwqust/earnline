import SwiftData
import SwiftUI

/// Project identity stays a lightweight preference over the existing
/// free-form `Entry.project` value. This screen is opened intentionally from
/// Settings, so its entry query never adds work to the everyday settings path.
struct ProjectIconsSettingsView: View {
    @Environment(\.modelContext) private var context
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
        .task { await reloadProjects() }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            Task { await reloadProjects() }
        }
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
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query(sort: \ProjectIconPreference.projectKey) private var preferences: [ProjectIconPreference]

    let projectName: String
    @State private var saveError: String?
    @State private var previewEntry: Entry

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
        let count = dynamicTypeSize.isAccessibilitySize ? 3 : 5
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: count)
    }

    private var selection: ProjectSymbol {
        ProjectIconResolver.symbol(for: projectName, in: preferences)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                ledgerPreview

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

                            LazyVGrid(columns: columns, spacing: 14) {
                                ForEach(category.symbols) { symbol in
                                    symbolButton(symbol)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
        }
        .navigationTitle("Project icon")
        .navigationBarTitleDisplayMode(.inline)
        .background(Theme.background)
        .saveErrorAlert($saveError, title: "Could not save project icon")
    }

    private var ledgerPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("In your ledger")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            // This is the exact renderer used by LedgerRowsView, not a visual
            // approximation. The preview changes together with its selected
            // symbol and inherits the user's current currency formatting.
            EntryRow(entry: previewEntry, projectSymbol: selection)
                .allowsHitTesting(false)
        }
        .onAppear { previewEntry.currencyCode = app.baseCurrencyCode }
    }

    private func symbolButton(_ symbol: ProjectSymbol) -> some View {
        let isSelected = selection == symbol
        return Button {
            select(symbol)
        } label: {
            Image(systemName: symbol.systemImageName)
                .font(.title3.weight(.semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(isSelected ? .white : .secondary)
                .frame(width: 52, height: 52)
                .background(
                    isSelected ? app.accentColor : Color(.tertiarySystemFill),
                    in: .circle
                )
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol.title)
        .accessibilityValue(isSelected ? "Selected" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("projectIcon.option.\(symbol.id)")
    }

    private func select(_ symbol: ProjectSymbol) {
        guard symbol != selection else { return }
        do {
            try ProjectIconPreferenceStore.set(symbol, for: projectName, in: context)
            saveError = app.save(context)
        } catch {
            saveError = error.localizedDescription
        }
    }
}

private struct ProjectCatalogLabel: View {
    let projectName: String
    let symbol: ProjectSymbol?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol?.systemImageName ?? "folder.fill")
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
            [.folder, .briefcase, .document, .package, .building, .tools, .chart, .people]
        case .creative:
            [.paintpalette, .sparkles, .camera, .video, .photo, .music, .pencil, .theater]
        case .digital:
            [.display, .app, .cloud, .terminal, .bolt, .cpu, .globe, .calendar]
        case .commerce:
            [.cart, .creditCard, .banknote, .megaphone, .storefront, .bag]
        }
    }
}
