import AppIntents
import Foundation
import SwiftData

/// A small AppEntity shadow model. App Intents never expose SwiftData models
/// directly because the system may keep an entity after its view disappears.
struct EarnlineClientEntity: AppEntity, Hashable, Sendable {
    static let defaultQuery = EarnlineClientQuery()
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Client"

    let id: String
    @Property(title: "Name") var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: LocalizedStringResource(stringLiteral: name))
    }

    init(id: UUID, name: String) {
        self.id = id.uuidString
        self.name = name
    }

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
    }
}

struct EarnlineClientQuery: EntityStringQuery {
    func entities(for identifiers: [EarnlineClientEntity.ID]) async throws -> [EarnlineClientEntity] {
        await MainActor.run {
            IntentLedgerStore.clients()
                .filter { identifiers.contains($0.id) }
        }
    }

    func entities(matching string: String) async throws -> [EarnlineClientEntity] {
        let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return await MainActor.run {
            IntentLedgerStore.clients().filter {
                query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)
            }
        }
    }

    func suggestedEntities() async throws -> [EarnlineClientEntity] {
        await MainActor.run { IntentLedgerStore.clients() }
    }
}

/// The app-intent entry point reopens the same workspace-scoped SwiftData file
/// the main app uses. It deliberately does not invent a second data store.
@MainActor
enum IntentLedgerStore {
    static func clients() -> [EarnlineClientEntity] {
        guard let (app, context) = try? EarnlineRuntime.shared.ledger(), !app.requireAppLock,
              let rows = try? context.fetch(FetchDescriptor<Client>()) else {
            return []
        }
        return rows
            .filter { !$0.isInvalidated }
            .sorted {
                if $0.sortIndex != $1.sortIndex { return $0.sortIndex < $1.sortIndex }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            .map { EarnlineClientEntity(id: "\(app.workspaceStoreIdentity)|\($0.id.uuidString)", name: $0.name) }
    }

    static func addIncome(amount: Decimal,
                          clientID: String,
                          project: String,
                          task: String, currencyCode: String? = nil) async throws {
        let (app, context) = try EarnlineRuntime.shared.ledger()
        let identity = app.workspaceStoreIdentity
        if app.requireAppLock {
            guard await AppLockAuth.evaluate(reason: String(localized: "Unlock your income ledger")) == .authenticated,
                  app.workspaceStoreIdentity == identity else { throw IntentLedgerError.openAppFirst }
        }
        guard clientID.hasPrefix(identity + "|"),
              let rawID = clientID.split(separator: "|").last,
              let clientID = UUID(uuidString: String(rawID)),
              let client = try context.fetch(FetchDescriptor<Client>(
                predicate: #Predicate { $0.id == clientID }
              )).first else {
            throw IntentLedgerError.clientNotFound
        }
        let cleanTask = Validation.trimmed(task, max: Limits.maxTaskLength)
        guard amount > 0,
              amount <= Limits.maxAmount,
              amount.rounded(2) == amount,
              !cleanTask.isEmpty else {
            throw IntentLedgerError.invalidIncome
        }
        let cleanProject = Validation.trimmed(project, max: Limits.maxProjectLength)
        var descriptor = FetchDescriptor<Entry>(
            predicate: #Predicate { $0.client?.id == clientID },
            sortBy: [SortDescriptor(\Entry.sortIndex, order: .forward)]
        )
        descriptor.fetchLimit = 1
        let minimumIndex = try context.fetch(descriptor).first?.sortIndex ?? 0
        let entry = Entry(
            amount: amount,
            currencyCode: currencyCode ?? app.baseCurrencyCode,
            project: cleanProject.isEmpty ? nil : cleanProject,
            task: cleanTask,
            date: .now,
            status: .paid,
            sortIndex: minimumIndex - 1
        )
        entry.client = client
        context.insert(entry)
        if let error = app.mutations.save(context) { throw IntentLedgerError.saveFailed(error) }
    }
}

enum IntentLedgerError: LocalizedError {
    case clientNotFound
    case invalidIncome
    case openAppFirst
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .openAppFirst: return String(localized: "Open and unlock Earnline to choose your ledger first.")
        case .saveFailed(let message): return message
        case .clientNotFound:
            return String(localized: "That client is no longer in this ledger.")
        case .invalidIncome:
            return String(localized: "Enter a positive amount with at most two decimal places and a description.")
        }
    }
}

/// “Add income” is intentionally a real local mutation. The app opens after
/// the intent so the regular sync lifecycle can pick up the dirty row.
struct AddIncomeIntent: AppIntent {
    static let title: LocalizedStringResource = "Add income"
    static let description = IntentDescription("Add a paid income line to an Earnline client.")
    static let openAppWhenRun = true
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Amount") var amount: String
    @Parameter(title: "Client") var client: EarnlineClientEntity
    @Parameter(title: "Description") var task: String
    @Parameter(title: "Project", default: "") var project: String
    @Parameter(title: "Currency") var currency: IntentCurrency?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$amount) for \(\.$client)") {
            \.$task
            \.$project
            \.$currency
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let amount = Validation.moneyAmount(from: amount) else {
            throw IntentLedgerError.invalidIncome
        }
        try await IntentLedgerStore.addIncome(
                amount: amount,
                clientID: client.id,
                project: project,
                task: task, currencyCode: currency?.rawValue
            )
        return .result(value: client.name, dialog: "Added income for \(client.name).")
    }
}

struct OpenEarnlineIntent: AppIntent {
    static let title: LocalizedStringResource = "Open income ledger"
    static let description = IntentDescription("Open the Earnline income ledger.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}

struct EarnlineShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddIncomeIntent(),
            phrases: [
                "Add income in \(.applicationName)",
                "Record income in \(.applicationName)",
            ],
            shortTitle: "Add income",
            systemImageName: "plus"
        )
        AppShortcut(
            intent: OpenEarnlineIntent(),
            phrases: ["Open \(.applicationName)"],
            shortTitle: "Open ledger",
            systemImageName: "book.closed"
        )
    }
}

/// Currency changes the new row only; historical values keep the live display rate.
enum IntentCurrency: String, AppEnum {
    case usd = "USD", eur = "EUR", gbp = "GBP", rub = "RUB", uah = "UAH"
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Currency"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .usd: "USD", .eur: "EUR", .gbp: "GBP", .rub: "RUB", .uah: "UAH",
    ]
}
