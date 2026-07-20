import Foundation
import Testing
@testable import earnline

@MainActor
struct LedgerCSVTests {
    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test func exportsRFC4180WithQuotesAndRussianText() {
        let record = LedgerCSV.ExportRecord(
            date: day(2026, 7, 20),
            client: "Студия, \"Север\"",
            project: "Q3, launch",
            task: "Баннер \"hero\"\nи мобильный экран",
            amount: Decimal(string: "1200.50")!,
            currencyCode: "USD",
            status: .inProgress,
            holdDate: day(2026, 7, 31)
        )

        let data = LedgerCSV.export([record])
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.hasPrefix("date,client,project,task,amount,currency_code,status,hold_date\r\n"))
        #expect(text.contains("\"Студия, \"\"Север\"\"\""))
        #expect(text.contains("\"Баннер \"\"hero\"\"\nи мобильный экран\""))

        let preview = LedgerCSV.preview(data)
        #expect(preview.issues.isEmpty)
        #expect(preview.rows.count == 1)
        #expect(preview.rows.first?.client == "Студия, \"Север\"")
        #expect(preview.rows.first?.project == "Q3, launch")
        #expect(preview.rows.first?.task == "Баннер \"hero\"\nи мобильный экран")
        #expect(preview.rows.first?.amount == Decimal(string: "1200.50"))
        #expect(preview.rows.first?.status == .inProgress)
    }

    @Test func acceptsRequiredColumnsAndFriendlyStatusValues() {
        let csv = """
        date,client,project,task,amount,currency code,status,hold date
        2026-01-04,Клиент,,Лендинг,500.25,eur,In progress,
        """

        let preview = LedgerCSV.preview(Data(csv.utf8))
        #expect(preview.isReadyToImport)
        #expect(preview.rows.first?.currencyCode == "EUR")
        #expect(preview.rows.first?.status == .inProgress)
    }

    @Test func flagsMalformedValuesWithoutOfferingAPartialImport() {
        let csv = """
        date,client,project,task,amount,currency_code,status,hold_date
        2026-02-31,Acme,,Task,100,USD,paid,
        2026-02-10,Acme,,Task,100,BTC,paid,
        """

        let preview = LedgerCSV.preview(Data(csv.utf8))
        #expect(preview.rows.isEmpty)
        #expect(preview.issues.count == 2)
        #expect(!preview.isReadyToImport)
    }

    @Test func rejectsAmountsThatWouldChangeOrFailDuringSync() {
        let csv = """
        date,client,project,task,amount,currency_code,status,hold_date
        2026-02-10,Acme,,Task,1.005,USD,paid,
        2026-02-11,Acme,,Task,1000000000.01,USD,paid,
        """

        let preview = LedgerCSV.preview(Data(csv.utf8))
        #expect(preview.rows.isEmpty)
        #expect(preview.issues.count == 2)
        #expect(!preview.isReadyToImport)
    }

    @Test func flagsDuplicateRowsInsideTheFileAndAgainstLedger() {
        let csv = """
        date,client,project,task,amount,currency_code,status,hold_date
        2026-01-12,Acme,Website,Homepage,300,USD,paid,
        2026-01-12,Acme,Website,Homepage,300,USD,paid,
        """
        let localDuplicates = LedgerCSV.preview(Data(csv.utf8))
        #expect(localDuplicates.rows.count == 2)
        #expect(localDuplicates.duplicateRowNumbers == Set([3]))
        #expect(!localDuplicates.isReadyToImport)

        let existing = Set([localDuplicates.rows[0].duplicateKey])
        let remoteDuplicates = LedgerCSV.preview(Data(csv.utf8), existingKeys: existing)
        #expect(remoteDuplicates.duplicateRowNumbers == Set([2, 3]))
    }

    @Test func quotedCommasDoNotShiftColumns() {
        let csv = """
        date,client,project,task,amount,currency_code,status,hold_date
        2026-01-12,"Acme, Inc.","Brand, web","Экран, 1",20,RUB,canceled,2026-02-01
        """

        let preview = LedgerCSV.preview(Data(csv.utf8))
        #expect(preview.isReadyToImport)
        #expect(preview.rows.first?.client == "Acme, Inc.")
        #expect(preview.rows.first?.project == "Brand, web")
        #expect(preview.rows.first?.task == "Экран, 1")
        #expect(preview.rows.first?.holdDate != nil)
    }
}
