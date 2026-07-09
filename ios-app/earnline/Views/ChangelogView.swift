import SwiftUI

/// "What's new" — renders the bundled `CHANGELOG.md` (the file the repo keeps
/// updated release to release) as a simple sectioned list. Pushed from
/// Settings › About inside the sheet's existing navigation stack.
struct ChangelogView: View {
    private let sections = ChangelogParser.parse(ChangelogParser.bundledChangelog)

    var body: some View {
        List {
            ForEach(sections) { section in
                Section {
                    ForEach(section.items) { item in
                        Text(item.text)
                            .font(.subheadline)
                            .foregroundStyle(Theme.label(0.85))
                    }
                } header: {
                    Text(section.title)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("What's new")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Minimal markdown outline reader for the changelog's fixed shape:
/// `##` dates and `###` groups become section headers, `-` lines become rows.
enum ChangelogParser {
    struct Item: Identifiable {
        let id = UUID()
        let text: String
    }

    struct Section: Identifiable {
        let id = UUID()
        let title: String
        var items: [Item]
    }

    static var bundledChangelog: String {
        guard let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return text
    }

    static func parse(_ markdown: String) -> [Section] {
        var sections: [Section] = []
        var date = ""
        for rawLine in markdown.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("### ") {
                let group = String(line.dropFirst(4))
                let title = date.isEmpty ? group : "\(date) — \(group)"
                sections.append(Section(title: title, items: []))
            } else if line.hasPrefix("## ") {
                date = String(line.dropFirst(3))
            } else if line.hasPrefix("- ") {
                let text = String(line.dropFirst(2))
                if sections.isEmpty {
                    sections.append(Section(title: date, items: []))
                }
                sections[sections.count - 1].items.append(Item(text: text))
            }
        }
        return sections.filter { !$0.items.isEmpty }
    }
}
