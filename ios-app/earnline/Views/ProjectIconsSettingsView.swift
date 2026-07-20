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
                    systemImage: "folder",
                    description: Text("Projects appear here after you add them to an income line.")
                )
            } else {
                List(projects) { project in
                    NavigationLink {
                        ProjectSymbolPickerView(
                            projectName: project.name
                        )
                    } label: {
                        Label(project.name, systemImage: symbol(for: project.name).systemImageName)
                            .lineLimit(2)
                    }
                    .accessibilityValue(symbol(for: project.name).title)
                }
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

    private func symbol(for projectName: String) -> ProjectSymbol {
        ProjectIconResolver.symbol(for: projectName, in: preferences)
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

    private var columns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 2 : 4
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: count)
    }

    private var selection: ProjectSymbol {
        ProjectIconResolver.symbol(for: projectName, in: preferences)
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(ProjectSymbol.allCases) { symbol in
                    symbolButton(symbol)
                }
            }
            .padding(16)
        }
        .navigationTitle(projectName)
        .navigationBarTitleDisplayMode(.inline)
        .background(Theme.background)
        .saveErrorAlert($saveError, title: "Could not save project icon")
    }

    private func symbolButton(_ symbol: ProjectSymbol) -> some View {
        let isSelected = selection == symbol
        return Button {
            select(symbol)
        } label: {
            VStack(spacing: 8) {
                Image(systemName: symbol.systemImageName)
                    .font(.title2.weight(.medium))
                    .symbolRenderingMode(.monochrome)
                    .frame(height: 28)
                Text(symbol.title)
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(isSelected ? app.accentColor : Theme.label)
            .frame(maxWidth: .infinity, minHeight: 72)
            .padding(.horizontal, 4)
            .background(
                isSelected ? app.accentColor.opacity(0.12) : Theme.surface,
                in: .rect(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? app.accentColor : Theme.hairline,
                                  lineWidth: isSelected ? 2 : 0.5)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
        }
    }
}
