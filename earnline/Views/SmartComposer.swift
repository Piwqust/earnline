import SwiftUI
import SwiftData

/// The income composer, built to match the Figma "Tertiary Item" exactly:
///   `+  [ $100 ]  [ Project ⌄ ] : [ Task ]                 [ ◐ ⌄ ]`
///   `↳  [ 29.06.26 ] · [ 📅 hold date ]`
/// Controlled with the chips and the keyboard Return key
/// (Amount → Return → Project → Return → Task → Return commits).
struct SmartComposer: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app

    @Binding var targetClient: Client?
    var initialText: String = ""
    var onClose: () -> Void

    enum Field: Hashable { case amount, project, task }
    @FocusState private var focus: Field?

    @State private var amountText = ""
    @State private var project = ""
    @State private var task = ""
    @State private var entryDate = Date()
    @State private var holdUntil: Date?
    @State private var status: EntryStatus = .inProgress
    @State private var currencyCode = "USD"
    @State private var showDatePicker = false
    @State private var showHoldPicker = false
    @State private var primed = false

    private var amountDecimal: Decimal? {
        guard let d = LineParser.decimal(from: amountText), d > 0 else { return nil }
        return Validation.clampAmount(d)
    }
    private var symbol: String { CurrencyFormatter.symbol(for: currencyCode) }
    private var canCommit: Bool {
        targetClient != nil && amountDecimal != nil
            && !Validation.trimmed(task, max: Limits.maxTaskLength).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Row 1 — content
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.label(0.5))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        amountChip
                        HStack(spacing: 4) {
                            projectChip
                            Text(":")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(Theme.label(0.6))
                            taskChip
                        }
                    }
                }
                .scrollClipDisabled()
                .frame(maxWidth: .infinity, alignment: .leading)

                statusChip
            }

            // Row 2 — date
            HStack(spacing: 6) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.label(0.4))
                dateChip
                Text("·").font(.system(size: 14)).foregroundStyle(Theme.label(0.6))
                holdChip
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .background(Theme.label(0.02), in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.label(0.1), lineWidth: 1))
        .onAppear(perform: prime)
    }

    // MARK: Row 1 chips

    private var amountChip: some View {
        chip(bg: Theme.label(0.10)) {
            HStack(spacing: 1) {
                Text(symbol)
                    .foregroundStyle(amountText.isEmpty ? Theme.label(0.4) : Theme.label)
                TextField("100", text: $amountText)
                    .fixedSize()
                    .frame(minWidth: 8)
                    .foregroundStyle(Theme.label)
                    .keyboardType(.numbersAndPunctuation)
                    .focused($focus, equals: .amount)
                    .submitLabel(.next)
                    .onChange(of: amountText) { _, v in amountText = Validation.sanitizeAmountInput(v) }
                    .onSubmit { focus = .project }
            }
            .font(.system(size: 18))
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
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.label(0.4))
            }
            .font(.system(size: 18))
        }
    }

    private var taskChip: some View {
        chip {
            TextField("Task", text: $task)
                .fixedSize()
                .frame(minWidth: 8)
                .foregroundStyle(Theme.label)
                .font(.system(size: 18))
                .focused($focus, equals: .task)
                .submitLabel(.done)
                .onChange(of: task) { _, v in task = Validation.capped(v, max: Limits.maxTaskLength) }
                .onSubmit(commit)
        }
    }

    private var statusChip: some View {
        Menu {
            ForEach(EntryStatus.allCases) { s in
                Button { status = s } label: { Label(s.title, systemImage: s.symbol) }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: status.symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(status.tint)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.label(0.4))
            }
            .padding(.horizontal, 6)
            .frame(height: 24)
            .background(Theme.label(0.05), in: .capsule)
        }
        .buttonStyle(.plain)
    }

    // MARK: Row 2 chips

    private var dateChip: some View {
        Button { showDatePicker = true } label: {
            chip(height: 20) {
                Text(DateFormat.dotted(entryDate))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.label(0.7))
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showDatePicker) {
            DatePicker("Date", selection: $entryDate, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .padding()
                .frame(minWidth: 320)
                .presentationCompactAdaptation(.popover)
        }
    }

    private var holdChip: some View {
        Button { showHoldPicker = true } label: {
            chip(height: 20) {
                HStack(spacing: 3) {
                    Image(systemName: "calendar")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.label(0.5))
                    Text(holdUntil.map { DateFormat.dotted($0) } ?? "hold date")
                        .font(.system(size: 14))
                        .foregroundStyle(holdUntil != nil ? Theme.label(0.8) : Theme.label(0.4))
                }
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showHoldPicker) {
            VStack(spacing: 12) {
                DatePicker("Hold until", selection: Binding(
                    get: { holdUntil ?? .now },
                    set: { holdUntil = $0 }
                ), displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                if holdUntil != nil {
                    Button("Clear", role: .destructive) { holdUntil = nil; showHoldPicker = false }
                }
            }
            .padding()
            .frame(minWidth: 320)
            .presentationCompactAdaptation(.popover)
        }
    }

    // MARK: Chip container

    private func chip<Content: View>(
        bg: Color = Theme.label(0.05),
        height: CGFloat = 28,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        content()
            .padding(.horizontal, 6)
            .frame(minWidth: 44, minHeight: height, maxHeight: height)
            .background(bg, in: .rect(cornerRadius: 5))
    }

    // MARK: Lifecycle / commit

    private func prime() {
        guard !primed else { return }
        primed = true
        currencyCode = app.baseCurrencyCode
        if !initialText.isEmpty {
            let parsed = LineParser.parse(initialText, defaultCurrency: app.baseCurrencyCode)
            if let amt = parsed.amount { amountText = NSDecimalNumber(decimal: amt).stringValue }
            project = parsed.project ?? ""
            task = parsed.task
            holdUntil = parsed.holdUntil
            status = parsed.status ?? .inProgress
            currencyCode = parsed.currencyCode
        }
        focus = .amount
    }

    private func commit() {
        guard let client = targetClient, let amount = amountDecimal else {
            focus = amountDecimal == nil ? .amount : .task
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }
        let cleanTask = Validation.trimmed(task, max: Limits.maxTaskLength)
        guard !cleanTask.isEmpty else {
            focus = .task
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }
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
        try? context.save()
        app.queueSync(context: context)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        withAnimation(.snappy) {
            amountText = ""; project = ""; task = ""
            holdUntil = nil; status = .inProgress; entryDate = Date()
        }
        focus = .amount
    }
}
