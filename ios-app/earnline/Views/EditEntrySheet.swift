import SwiftUI
import SwiftData

/// Full editor for one income line: the system compose-sheet toolbar (✕/✓
/// role buttons, as in Mail), a hero amount with the currency picker beneath
/// it, a segmented status control, then icon-led grouped cards for the
/// project, task, client, and schedule.
struct EditEntrySheet: View {
    /// Fixed values for the noninteractive, in-memory account-preview story.
    /// Production call sites leave this as `nil`, so the editor continues to
    /// load and save the live SwiftData model exactly as before.
    struct PreviewValues {
        let amount: Decimal
        let currencyCode: String
        let project: String
        let task: String
        let status: EntryStatus
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @AppStorage(ProjectIconAppearance.userDefaultsKey) private var projectIconAppearanceRaw = ProjectIconAppearance.fill.rawValue
    @Query(sort: \ProjectIconPreference.projectKey) private var projectIconPreferences: [ProjectIconPreference]
    @Bindable var entry: Entry
    let clients: [Client]
    /// The decorative account-preview story can animate this picker while the
    /// production editor keeps its existing data and interaction behavior.
    var previewStatus: EntryStatus? = nil
    /// Internal-only timing for the account tour's status confirmation.
    /// Production callers leave this nil and retain the native picker motion.
    var previewStatusAnimationDuration: TimeInterval? = nil
    var previewValues: PreviewValues? = nil

    @State private var amountText: String = ""
    @State private var project: String = ""
    @State private var task: String = ""
    @State private var currencyCode = "USD"
    @State private var date: Date = .now
    @State private var hasHold = false
    @State private var holdDate: Date = .now
    @State private var status: EntryStatus = .paid
    @State private var selectedClient: Client?
    @State private var saveError: String?
    @State private var saveFeedback = 0
    @FocusState private var amountFocused: Bool

    private var amountDecimal: Decimal? {
        guard let d = LineParser.decimal(from: amountText), d > 0 else { return nil }
        return Validation.clampAmount(d)
    }
    private var symbol: String { CurrencyFormatter.symbol(for: currencyCode) }
    private var projectIconAppearance: ProjectIconAppearance {
        ProjectIconAppearance(rawValue: projectIconAppearanceRaw) ?? .fill
    }
    private var canSave: Bool {
        amountDecimal != nil
            && selectedClient != nil
            && !Validation.trimmed(task, max: Limits.maxTaskLength).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                amountHero
                    .padding(.bottom, 2)

                statusSegmented
                    .animation(
                        previewStatusAnimationDuration.map { .easeInOut(duration: $0) },
                        value: previewStatus
                    )

                section("Details") {
                    VStack(spacing: 10) {
                        detailsCard
                        clientCard
                    }
                }

                section("Schedule") { scheduleCard }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .scrollDismissesKeyboard(.interactively)
        // Apple's ready-made compose-sheet header (Mail's ✕/send bar):
        // system ✕/✓ role buttons in a navigation toolbar. See `sheetEditorHeader`.
        .sheetEditorHeader("Edit line",
                           saveEnabled: canSave,
                           onCancel: { dismiss() },
                           onSave: save)
        .onAppear(perform: load)
        .onChange(of: previewStatus) { _, newStatus in
            if let newStatus { status = newStatus }
        }
        .onChange(of: date) { _, newValue in
            if holdDate < newValue { holdDate = newValue }
        }
        .saveErrorAlert($saveError, title: "Could not save line")
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.background)
        .sensoryFeedback(.selection, trigger: status)
        .sensoryFeedback(.impact(weight: .light), trigger: saveFeedback)
    }

    private func section(_ title: LocalizedStringKey,
                         @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            CardHeader(title)
            content()
        }
    }

    // MARK: Amount hero

    /// Big centered amount with a leading currency symbol, and the currency
    /// picker as its subtitle — the Figma "$200 / $ USD ⌄" hero.
    private var amountHero: some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(symbol)
                TextField("0", text: $amountText)
                    .fixedSize()
                    .multilineTextAlignment(.leading)
                    .keyboardType(.numbersAndPunctuation)
                    .focused($amountFocused)
                    .onChange(of: amountText) { _, v in amountText = Validation.sanitizeAmountInput(v) }
                    .accessibilityLabel("Amount")
            }
            .appFont(56, .bold, design: .rounded, relativeTo: .largeTitle)
            .monospacedDigit()
            .foregroundStyle(amountDecimal == nil ? Theme.tertiaryLabel : Theme.label)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
            .onTapGesture { amountFocused = true }

            currencyPicker
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    /// Native menu picker beneath the amount — rows lead with their currency
    /// glyph in the Liquid Glass menu panel.
    private var currencyPicker: some View {
        Menu {
            Picker("Currency", selection: $currencyCode) {
                ForEach(AppModel.supportedCurrencyCodes, id: \.self) { code in
                    Label(code, systemImage: CurrencyFormatter.symbolName(for: code)).tag(code)
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 6) {
                Text("\(symbol) \(currencyCode)")
                    .appFont(17)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Currency")
        .accessibilityValue(currencyCode)
    }

    // MARK: Status (segmented)

    private var statusSegmented: some View {
        Picker("Status", selection: $status) {
            ForEach(EntryStatus.allCases) { s in
                Text(s.title).tag(s)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    // MARK: Details (icon-led editable rows)

    private var detailsCard: some View {
        ChromeCard {
            ChromeRow(icon: ProjectIconResolver.symbol(for: project, in: projectIconPreferences)
                .systemImageName(for: projectIconAppearance)) {
                TextField("Project", text: $project)
                    .foregroundStyle(Theme.label)
                    .onChange(of: project) { _, v in project = Validation.capped(v, max: Limits.maxProjectLength) }
                    .accessibilityLabel("Project")
            }
            ChromeDivider()
            ChromeRow(icon: "text.document", alignTop: true) {
                TextField("Describe the work", text: $task, axis: .vertical)
                    .lineLimit(1...4)
                    .foregroundStyle(Theme.label)
                    .padding(.vertical, 15)
                    .onChange(of: task) { _, v in task = Validation.capped(v, max: Limits.maxTaskLength) }
                    .accessibilityLabel("Task")
            }
        }
    }

    private var clientCard: some View {
        ChromeCard {
            ChromeRow(icon: "person.crop.circle") {
                Text("Client").foregroundStyle(Theme.label)
                Spacer()
                clientMenu
            }
        }
    }

    /// Client picker with a truncating label — a long client name shortens in
    /// the middle instead of wrapping the row. The menu content stays a native
    /// inline picker (system checkmark, Liquid Glass panel).
    private var clientMenu: some View {
        Menu {
            Picker("Client", selection: $selectedClient) {
                ForEach(clients) { client in
                    Text(client.name).tag(Optional(client))
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 6) {
                Text(selectedClient?.name ?? String(localized: "Choose"))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: 190, alignment: .trailing)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Client")
        .accessibilityValue(selectedClient?.name ?? "")
    }

    // MARK: Schedule

    private var scheduleCard: some View {
        ChromeCard {
            ChromeRow(icon: "calendar") {
                Text("Date").foregroundStyle(Theme.label)
                Spacer()
                DatePicker("", selection: $date, displayedComponents: .date)
                    .labelsHidden()
            }
            ChromeDivider()
            ChromeRow(icon: "hourglass") {
                Toggle(isOn: $hasHold.animation()) {
                    Text("Hold until").foregroundStyle(Theme.label)
                }
            }
            if hasHold {
                ChromeDivider()
                ChromeRow(icon: "calendar.badge.clock") {
                    Text("Hold date").foregroundStyle(Theme.label)
                    Spacer()
                    DatePicker("", selection: $holdDate, in: date..., displayedComponents: .date)
                        .labelsHidden()
                }
            }
        }
    }

    // MARK: Data

    private func load() {
        if let previewValues {
            amountText = NSDecimalNumber(decimal: previewValues.amount).stringValue
            currencyCode = previewValues.currencyCode
            project = previewValues.project
            task = previewValues.task
            status = previewStatus ?? previewValues.status
            selectedClient = clients.first
            return
        }
        guard !entry.isInvalidated else { return }
        amountText = NSDecimalNumber(decimal: entry.amount).stringValue
        currencyCode = entry.currencyCode
        project = entry.project ?? ""
        task = entry.task
        date = entry.date
        status = entry.status
        if let h = entry.holdUntil { hasHold = true; holdDate = h }
        selectedClient = entry.client
    }

    private func save() {
        guard let amount = amountDecimal else { return }
        // A sync pull can delete the line while it's being edited; writing to
        // the invalidated model would trap. The edit is lost either way — the
        // row no longer exists anywhere — so just close.
        guard !entry.isInvalidated else {
            dismiss()
            return
        }
        entry.amount = amount
        entry.currencyCode = currencyCode
        let p = Validation.trimmed(project, max: Limits.maxProjectLength)
        entry.project = p.isEmpty ? nil : p
        entry.task = Validation.trimmed(task, max: Limits.maxTaskLength)
        entry.date = date
        entry.holdUntil = hasHold ? holdDate : nil
        entry.status = status
        if let c = selectedClient { entry.client = c }
        entry.markDirty()
        if let error = app.save(context) {
            saveError = error
        } else {
            saveFeedback += 1
            dismiss()
        }
    }
}
