import AppIntents
import SwiftUI
import WidgetKit

struct EarningsWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: LedgerWidgetSnapshot?
}

struct EarningsWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> EarningsWidgetEntry { .init(date: .now, snapshot: nil) }
    func getSnapshot(in context: Context, completion: @escaping (EarningsWidgetEntry) -> Void) {
        completion(.init(date: .now, snapshot: LedgerWidgetSnapshot.read()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<EarningsWidgetEntry>) -> Void) {
        completion(Timeline(entries: [.init(date: .now, snapshot: LedgerWidgetSnapshot.read())],
                            policy: .after(.now.addingTimeInterval(30 * 60))))
    }
}

struct EarningsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: EarningsWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let snapshot = entry.snapshot, !snapshot.hidesAmounts {
                Text(snapshot.month).font(.caption).foregroundStyle(.secondary)
                Text(snapshot.primary).font(family == .systemSmall ? .title2.bold() : .headline)
                    .minimumScaleFactor(0.7).lineLimit(1).privacySensitive()
                Text(snapshot.secondary).font(.subheadline).foregroundStyle(.secondary).privacySensitive()
                if family == .systemSmall || family == .systemMedium {
                    Spacer(minLength: 0)
                    Text(snapshot.date, style: .time).font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                Label("Earnline", systemImage: "book.closed")
                Text("Open your ledger").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(.background, for: .widget)
        .widgetURL(URL(string: "com.earnline.app://ledger"))
    }
}

struct EarningsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "earnline.earnings", provider: EarningsWidgetProvider()) { EarningsWidgetView(entry: $0) }
            .configurationDisplayName("Monthly earnings")
            .description("Your latest earnings in both currencies.")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

enum LedgerControlDestination: String, AppEnum {
    case addIncome
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Ledger action"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [.addIncome: "Add income"]
}

struct OpenIncomeControlIntent: OpenIntent {
    static let title: LocalizedStringResource = "Add income"
    @Parameter(title: "Action") var target: LedgerControlDestination
    init() { target = .addIncome }

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "com.earnline.app://add-income")!))
    }
}

struct AddIncomeControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "earnline.addIncome") {
            ControlWidgetButton(action: OpenIncomeControlIntent()) { Label("Add income", systemImage: "plus") }
        }
        .displayName("Add income")
    }
}

@main
struct EarnlineWidgets: WidgetBundle {
    var body: some Widget {
        EarningsWidget()
        AddIncomeControl()
    }
}
