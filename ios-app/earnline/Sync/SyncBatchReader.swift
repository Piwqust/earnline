import Foundation
import Supabase

struct SyncBatchReader {
    struct Cursor: Codable { let timestamp: String; let id: UUID }
    struct Parameters: Encodable {
        let workspaceID: String
        let since: [String: String?]
        let before: [String: Cursor]
        let done: [String]
        enum CodingKeys: String, CodingKey {
            case workspaceID = "p_workspace_id", since = "p_since", before = "p_before", done = "p_done"
        }
    }

    struct Page: Decodable {
        var clients: [RemoteClient]
        var headings: [RemoteHeading]
        var entries: [RemoteEntry]
        var projectIcons: [RemoteProjectIcon]
        var monthReviews: [RemoteMonthReview]
        enum CodingKeys: String, CodingKey {
            case clients = "earnline_clients", headings = "earnline_headings", entries = "earnline_entries"
            case projectIcons = "earnline_project_icons", monthReviews = "earnline_month_reviews"
        }
    }

    @MainActor
    static func read(client: SupabaseClient, workspace: String, since: [String: Date?]) async throws -> Page? {
        var cursors: [String: Cursor] = [:]
        var done = Set<String>()
        var result = Page(clients: [], headings: [], entries: [],
                          projectIcons: [], monthReviews: [])
        repeat {
            try Task.checkCancellation()
            let page: Page
            do {
                page = try await client.rpc("earnline_pull_page", params: Parameters(
                    workspaceID: workspace,
                    since: since.mapValues { $0.map(SyncDateCodec.timestampString) },
                    before: cursors, done: Array(done)
                )).execute().value
            } catch let error as PostgrestError where error.code == "PGRST202" || error.code == "42883" {
                // Older installations keep using their working table transport.
                return nil
            }
            func append<Row: SyncCursorRecord>(_ rows: [Row], to output: inout [Row], table: String) throws {
                guard !done.contains(table) else { return }
                output.append(contentsOf: rows)
                guard rows.count == 250, let last = rows.last else { done.insert(table); return }
                guard SyncDateCodec.parseTimestamp(last.syncCursorTimestamp) != nil,
                      cursors[table]?.id != last.id else { throw SyncError.invalidRemoteCursor(table: table) }
                cursors[table] = Cursor(timestamp: last.syncCursorTimestamp, id: last.id)
            }
            try append(page.clients, to: &result.clients, table: "earnline_clients")
            try append(page.headings, to: &result.headings, table: "earnline_headings")
            try append(page.entries, to: &result.entries, table: "earnline_entries")
            try append(page.projectIcons, to: &result.projectIcons, table: "earnline_project_icons")
            try append(page.monthReviews, to: &result.monthReviews, table: "earnline_month_reviews")
        } while done.count < 5
        return result
    }
}
