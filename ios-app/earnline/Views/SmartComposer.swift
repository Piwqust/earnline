import SwiftUI
import SwiftData

/// The inline "mini creation window". Figma chip aesthetic, with a multi-line
/// task (Return inserts a line break) and a Submit button to commit.
/// Amount → Return → Project → Return → Task (multi-line) → Submit.
struct SmartComposer: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let client: Client
    /// The month this composer is anchored to, so a new line lands in the
    /// section the user tapped "+ Line" in — not in today's month.
    var month: Date = .now
    var initialText: String = ""
    /// Decorative previews reuse the real composer but must never summon the
    /// keyboard or move VoiceOver focus away from the actual account screen.
    var automaticallyFocus = true

    @Query(sort: \Entry.createdAt, order: .reverse) private var allEntries: [Entry]

    enum Field: Hashable { case amount, project, task }
    @FocusState private var focus: Field?

    @State private var amountText = ""
    @State private var project = ""
    @State private var task = ""
    @State private var entryDate = Date()
    @State private var holdUntil: Date?
    @State private var status: EntryStatus = .paid
    @State private var currencyCode = "USD"
    @State private var showDatePicker = false
    @State private var showHoldPicker = false
    @State private var primed = false
    @State private var saveError: String?

    private var amountDecimal: Decimal? {
        guard let d = LineParser.decimal(from: amountText), d > 0 else { return nil }
        return Validation.clampAmount(d)
    }
    private var symbol: String { CurrencyFormatter.symbol(for: currencyCode) }
    private var canCommit: Bool {
        amountDecimal != nil && !Validation.trimmed(task, max: Limits.maxTaskLength).isEmpty
    }

    /// Where the date picker starts: today when composing in the current month,
    /// otherwise the first of the anchored month so the line lands in the right
    /// section.
    private var defaultDate: Date {
        Calendar.current.isDate(month, equalTo: .now, toGranularity: .month)
            ? Date()
            : DateFormat.monthStart(of: month)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Chips — single row: amount · project · status
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .appFont(12, .semibold)
                    .foregroundStyle(Theme.label(0.5))
                    .frame(height: 28)
                amountChip
                projectChip
                statusChip
                Spacer(minLength: 0)
            }

            // Task — full width, multi-line (line breaks allowed)
            taskField

            // Date row + Submit
            HStack(spacing: 6) {
                Image(systemName: "arrow.turn.down.right")
                    .appFont(10)
                    .foregroundStyle(Theme.label(0.4))
                dateChip
                Text("·").appFont(14).foregroundStyle(Theme.label(0.6))
                holdChip
                Spacer(minLength: 8)
                submitButton
            }
        }
        .padding(12)
        .background(Theme.label(0.02), in: .rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .foregroundStyle(Theme.label(0.18))
        )
        .onAppear(perform: prime)
        .onChange(of: entryDate) { _, newValue in
            if let holdUntil, holdUntil < newValue { self.holdUntil = newValue }
        }
        .saveErrorAlert($saveError, title: "Could not save line")
    }

    // MARK: Chips

    private var amountChip: some View {
        chip(bg: Theme.label(0.10)) {
            HStack(spacing: 1) {
                Menu {
                    // Native inline picker — the system carries the selection
                    // checkmark in the Liquid Glass menu.
                    Picker("Currency", selection: $currencyCode) {
                        ForEach(AppModel.supportedCurrencyCodes, id: \.self) { code in
                            Label(code, systemImage: CurrencyFormatter.symbolName(for: code)).tag(code)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Text(symbol)
                        .foregroundStyle(amountText.isEmpty ? Theme.label(0.4) : Theme.label)
                        .frame(minWidth: 18)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Currency")
                .accessibilityValue(currencyCode)
                TextField("100", text: $amountText)
                    .fixedSize()
                    .frame(minWidth: 8)
                    .foregroundStyle(Theme.label)
                    .keyboardType(.numbersAndPunctuation)
                    .focused($focus, equals: .amount)
                    .submitLabel(.next)
                    .onChange(of: amountText) { _, v in amountText = Validation.sanitizeAmountInput(v) }
                    .onSubmit { focus = .project }
                    .accessibilityLabel("Amount")
            }
            .appFont(18)
        }
    }

    private var projectChip: some View {
        chip {
            HStack(spacing: 4) {
                TextField("Project", text: $project)
                    .fixedSize()
                    .frame(minWidth: 8)
                    .foregroundStyle(Theme.label)
                    .focused($focus, equals: .project)
                    .submitLabel(.next)
                    .onChange(of: project) { _, v in project = Validation.capped(v, max: Limits.maxProjectLength) }
                    .onSubmit { focus = .task }
                    .accessibilityLabel("Project")
                projectMenu
            }
            .appFont(18)
        }
    }

    /// Tap the chevron to pick an existing project; type in the field to create a new one.
    @ViewBuilder private var projectMenu: some View {
        if existingProjects.isEmpty {
            Image(systemName: "chevron.down")
                .appFont(9, .semibold)
                .foregroundStyle(Theme.label(0.35))
        } else {
            Menu {
                Section("Existing projects") {
                    Picker("Existing projects", selection: Binding(
                        get: { project },
                        set: { project = $0; focus = .task }
                    )) {
                        ForEach(existingProjects, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .pickerStyle(.inline)
                }
            } label: {
                Image(systemName: "chevron.down")
                    .appFont(11, .semibold)
                    .foregroundStyle(Theme.label(0.45))
                    .frame(width: 22, height: 24)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    /// Distinct project names already used anywhere, most-recent first.
    private var existingProjects: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for entry in allEntries {
            guard let raw = entry.project?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { continue }
            if seen.insert(raw.lowercased()).inserted { result.append(raw) }
            if result.count >= 12 { break }
        }
        return result
    }

    private var statusChip: some View {
        Menu {
            // Native inline picker — the system draws the selection checkmark
            // in the Liquid Glass menu (same idiom as EntryRow).
            Section("Status") {
                Picker("Status", selection: $status) {
                    ForEach(EntryStatus.allCases) { s in
                        Text(s.title).tag(s)
                    }
                }
                .pickerStyle(.inline)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: status.symbol)
                    .appFont(13)
                    .foregroundStyle(status.tint)
                    .contentTransition(.symbolEffect(.replace))
                    .animation(.snappy(duration: 0.3), value: status)
                Image(systemName: "chevron.down").appFont(9, .semibold).foregroundStyle(Theme.label(0.4))
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(Theme.label(0.05), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Status")
        .accessibilityValue(status.title)
    }

    private var taskField: some View {
        TextField("Task", text: $task, axis: .vertical)
            .appFont(18)
            .foregroundStyle(Theme.label)
            .lineLimit(1...5)
            .focused($focus, equals: .task)
            .onChange(of: task) { _, v in task = Validation.capped(v, max: Limits.maxTaskLength) }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.label(0.05), in: .rect(cornerRadius: 8))
            .accessibilityLabel("Task")
    }

    private var dateChip: some View {
        Button { showDatePicker = true } label: {
            chip(height: 22) {
                Text(DateFormat.dotted(entryDate)).appFont(14).foregroundStyle(Theme.label(0.7))
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showDatePicker) {
            DatePickerPopover(title: "Income date", date: $entryDate, minimumDate: nil,
                              clearTitle: nil, onClear: nil, onDone: { showDatePicker = false })
        }
    }

    private var holdChip: some View {
        Button { showHoldPicker = true } label: {
            chip(height: 22) {
                HStack(spacing: 3) {
                    Image(systemName: "calendar").appFont(10).foregroundStyle(Theme.label(0.5))
                    Text(holdUntil.map { DateFormat.dotted($0) } ?? String(localized: "hold date"))
                        .appFont(14)
                        .foregroundStyle(holdUntil != nil ? Theme.label(0.8) : Theme.label(0.4))
                }
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showHoldPicker) {
            DatePickerPopover(
                title: "Hold until",
                date: Binding(get: { holdUntil ?? entryDate }, set: { holdUntil = max($0, entryDate) }),
                minimumDate: entryDate,
                clearTitle: holdUntil == nil ? nil : "Clear hold",
                onClear: { holdUntil = nil; showHoldPicker = false },
                onDone: { showHoldPicker = false }
            )
        }
    }

    private var submitButton: some View {
        Button(action: commit) {
            Image(systemName: "arrow.up")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(canCommit ? .white : Theme.label(0.3))
                .frame(width: 34, height: 34)
                .glassEffect(
                    .regular
                        .tint(canCommit ? app.accentColor : nil)
                        .interactive(canCommit),
                    in: .circle
                )
                .padding(5)
                .contentShape(.circle)
                // The trigger value is frozen under Reduce Motion, so the
                // bounce simply never fires.
                .symbolEffect(.bounce, value: reduceMotion ? false : canCommit)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add line")
        .accessibilityIdentifier("composer.submit")
        .disabled(!canCommit)
        .animation(.snappy, value: canCommit)
    }

    private func chip<Content: View>(bg: Color = Theme.label(0.05), height: CGFloat = 28,
                                     @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 7)
            .frame(minWidth: 44, minHeight: height)
            .background(bg, in: .rect(cornerRadius: 6))
    }

    // MARK: Lifecycle / commit

    private func prime() {
        guard !primed else { return }
        primed = true
        currencyCode = app.baseCurrencyCode
        entryDate = defaultDate
        if !initialText.isEmpty {
            let parsed = LineParser.parse(initialText, defaultCurrency: app.baseCurrencyCode)
            if let amt = parsed.amount { amountText = NSDecimalNumber(decimal: amt).stringValue }
            project = parsed.project ?? ""
            task = parsed.task
            holdUntil = parsed.holdUntil
            status = parsed.status ?? .paid
            currencyCode = parsed.currencyCode
        }
        if automaticallyFocus { focus = .amount }
    }

    private func commit() {
        guard let amount = amountDecimal else { focus = .amount; warn(); return }
        let cleanTask = Validation.trimmed(task, max: Limits.maxTaskLength)
        guard !cleanTask.isEmpty else { focus = .task; warn(); return }
        let cleanProject = Validation.trimmed(project, max: Limits.maxProjectLength)
        let minIndex = client.entries.map(\.sortIndex).min() ?? 0
        let entry = Entry(
            amount: amount,
            currencyCode: currencyCode,
            project: cleanProject.isEmpty ? nil : cleanProject,
            task: cleanTask,
            date: entryDate,
            holdUntil: holdUntil,
            status: status,
            sortIndex: minIndex - 1
        )
        entry.client = client
        context.insert(entry)
        if let error = app.save(context) {
            // `AppModel.save` has already rolled the failed transaction back.
            // Do not mutate the context again here, or this error path itself
            // becomes a new pending delete.
            saveError = error
        } else {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.snappy) {
                amountText = ""; project = ""; task = ""
                holdUntil = nil; status = .paid; entryDate = defaultDate
                currencyCode = app.baseCurrencyCode
            }
            focus = .amount
        }
    }

    private func warn() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}

/// A compact graphical date picker shown as an anchored popover (tooltip), not a sheet.
struct DatePickerPopover: View {
    let title: LocalizedStringKey
    @Binding var date: Date
    var minimumDate: Date?
    var clearTitle: LocalizedStringKey?
    var onClear: (() -> Void)?
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .appFont(15, .semibold)
                    .foregroundStyle(Theme.label(0.85))
                Spacer()
                Button("Done", action: onDone)
                    .appFont(15, .semibold)
            }
            picker
                .datePickerStyle(.graphical)
            if let clearTitle, let onClear {
                Button(role: .destructive, action: onClear) {
                    Label(clearTitle, systemImage: "xmark.circle")
                        .appFont(14, .medium)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .frame(width: 320)
        .presentationCompactAdaptation(.popover)
    }

    @ViewBuilder private var picker: some View {
        if let minimumDate {
            DatePicker(title, selection: $date, in: minimumDate..., displayedComponents: .date).labelsHidden()
        } else {
            DatePicker(title, selection: $date, displayedComponents: .date).labelsHidden()
        }
    }
}
