import Foundation

struct LedgerWidgetSnapshot: Codable {
    static let group = "group.com.earnline.app"
    static let fileName = "earnline-widget.json"
    let date: Date
    let month: String
    let primary: String
    let secondary: String
    let hidesAmounts: Bool

    static var directory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
    }

    static func read() -> Self? {
        guard let directory, let data = try? Data(contentsOf: directory.appendingPathComponent(fileName)) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    func write() throws {
        guard let directory = Self.directory else { return }
        try JSONEncoder().encode(self).write(to: directory.appendingPathComponent(Self.fileName),
                                             options: [.atomic, .completeFileProtection])
    }
}
