import Foundation
import SwiftData

enum IncomeLedgerImporter {
    static let bundledLedger = """
    — Доходы за апрель от Лунной мастерской

    + $320 Сад комет: Иллюстрации для старта
    + $260 Карманная планета: Экран приветствия
    + $180 Почта для звёзд: Набор эмодзи
    + $310 Тихий космодром: Карта маршрутов

    $1070

    — Доходы за май от Лунной мастерской

    + $480 Сад комет: Атлас созвездий
    + $120 Почта для звёзд: Марки для писем
    + $560 Бархатный портал: Главный экран
    + $220 Клуб ночных поездов: Билеты и расписание
    + $150 Тихий космодром: Иконки навигации
    + $360 Чайная на Луне: Меню сезона затмений
    + $190 Карманная планета: Анимация орбит
    + $210 Радио для драконов: Обложки эпизодов
    + $430 Бархатный портал: Кабинет путешественника
    + $170 Маяк облаков: Движение волн
    + $280 Сад комет: Набор наклеек
    + $240 Клуб ночных поездов: Плакаты станций

    $3410

    — Доходы за май от Бюро облачных китов
    + 18k ₽ Маяк облаков: Плакаты приливов
    + 12k ₽ Радио для драконов: Гайд ведущего
    + 9k ₽ Чайная на Луне: Карта вкусов

    Доходы за май. Итого: $3410 / 39 000 ₽


    — Доходы за июнь от Аркадии северного сияния
    + $720 Бархатный портал: Путеводитель по мирам
    + $140 Карманная планета: Карточки спутников
    + $380 Тихий космодром: Панель диспетчера
    + $260 Почта для звёзд: Анимация отправки

    — Доходы за июнь от Лунной мастерской
    + $110 Сад комет: Титульная сцена
    + $340 Клуб ночных поездов: Билетный автомат
    + $90 Чайная на Луне: Значки сортов
    + $230 Маяк облаков: Погода для моряков
    + $160 Радио для драконов: Визуал эфира

    $2430

    — Доходы за июнь от Бюро облачных китов
    + 14k ₽ Маяк облаков: Ночные сигналы
    """

    struct ParsedEntry: Equatable {
        let id: UUID
        let clientName: String
        let amount: Decimal
        let currencyCode: String
        let project: String?
        let task: String
        let date: Date
        let sortIndex: Int
        let rawLine: String
    }

    @discardableResult
    static func importBundledLedger(into context: ModelContext, year: Int = Calendar.current.component(.year, from: .now)) throws -> Int {
        let parsed = parse(bundledLedger, year: year)
        guard !parsed.isEmpty else { return 0 }

        // A failed read is not an empty ledger. Continuing would create
        // duplicate clients or entries during a later import, so propagate it
        // to the existing Settings error surface instead.
        let existingClients = try context.fetch(FetchDescriptor<Client>())
        var clientsByName = Dictionary(uniqueKeysWithValues: existingClients.map { ($0.name.normalizedLedgerKey, $0) })
        let existingEntries = try context.fetch(FetchDescriptor<Entry>())
        let existingEntryIDs = Set(existingEntries.map(\.id))
        var inserted = 0

        for record in parsed {
            let clientKey = record.clientName.normalizedLedgerKey
            let client: Client
            if let existing = clientsByName[clientKey] {
                client = existing
            } else {
                let newClient = Client(id: clientID(record.clientName),
                                       name: record.clientName,
                                       colorHex: colorHex(for: clientsByName.count),
                                       sortIndex: clientsByName.count,
                                       createdAt: record.date,
                                       updatedAt: record.date)
                context.insert(newClient)
                clientsByName[clientKey] = newClient
                client = newClient
                inserted += 1
            }

            guard !existingEntryIDs.contains(record.id) else { continue }
            let entry = Entry(id: record.id,
                              amount: record.amount,
                              currencyCode: record.currencyCode,
                              project: record.project,
                              task: record.task,
                              date: record.date,
                              status: .paid,
                              sortIndex: record.sortIndex,
                              createdAt: record.date,
                              updatedAt: record.date)
            entry.client = client
            context.insert(entry)
            inserted += 1
        }

        try context.save()
        return inserted
    }

    static func parse(_ raw: String, year: Int) -> [ParsedEntry] {
        var currentMonth: Int?
        var currentClient: String?
        var sortIndexBySection: [String: Int] = [:]
        var results: [ParsedEntry] = []

        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if let section = parseSection(trimmed) {
                currentMonth = section.month
                currentClient = section.client
                continue
            }

            guard trimmed.hasPrefix("+"),
                  let month = currentMonth,
                  let client = currentClient else { continue }

            let sectionKey = "\(year)-\(month)-\(client.normalizedLedgerKey)"
            let sortIndex = sortIndexBySection[sectionKey, default: 0]
            sortIndexBySection[sectionKey] = sortIndex + 1

            let parsed = LineParser.parse(trimmed, defaultCurrency: "USD")
            guard let amount = parsed.amount else { continue }

            let date = date(year: year, month: month, day: min(28, sortIndex + 1))
            let task = parsed.task.isEmpty ? "Income" : parsed.task
            results.append(ParsedEntry(
                id: entryID(client: client, year: year, month: month, sortIndex: sortIndex, rawLine: trimmed),
                clientName: client,
                amount: amount,
                currencyCode: parsed.currencyCode,
                project: parsed.project,
                task: task,
                date: date,
                sortIndex: sortIndex,
                rawLine: trimmed
            ))
        }

        return results
    }

    private static func parseSection(_ line: String) -> (month: Int, client: String)? {
        let isIncomeHeading = line.localizedCaseInsensitiveContains("Доходы за")
            || line.localizedCaseInsensitiveContains("Income for")
        guard isIncomeHeading,
              let month = LineParser.monthMap.first(where: { line.localizedCaseInsensitiveContains($0.key) })?.value,
              let range = line.range(of: " from ", options: [.caseInsensitive, .diacriticInsensitive])
                ?? line.range(of: " от ", options: [.caseInsensitive, .diacriticInsensitive]) else {
            return nil
        }
        let client = String(line[range.upperBound...])
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "—-")))
        return client.isEmpty ? nil : (month, client)
    }

    static func clientID(_ name: String) -> UUID {
        DeterministicID.uuid("earnline-client:\(name.normalizedLedgerKey)")
    }

    private static func entryID(client: String, year: Int, month: Int, sortIndex: Int, rawLine: String) -> UUID {
        DeterministicID.uuid("earnline-entry:\(year)-\(month)-\(client.normalizedLedgerKey)-\(sortIndex)-\(rawLine)")
    }

    private static func colorHex(for index: Int) -> String {
        Theme.clientPalette[index % Theme.clientPalette.count]
    }

    private static func date(year: Int, month: Int, day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day)) ?? .now
    }
}

private extension String {
    var normalizedLedgerKey: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
