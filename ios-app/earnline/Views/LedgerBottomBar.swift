import SwiftUI

/// Native SwiftUI bottom chrome. Keeping it out of a UIKit-backed bottom
/// toolbar avoids attaching `UIKitToolbar` directly to the hosting controller,
/// while the glass button style preserves iOS 26's system material and motion.
struct LedgerBottomBar: View {
    let clients: [Client]
    let pendingCount: Int
    let onSearch: () -> Void
    let onInsights: () -> Void
    let onPending: () -> Void
    let onSettings: () -> Void
    let onIncome: (Client?) -> Void
    let onNewClient: () -> Void
    let onNewHeading: () -> Void
    let onPasteLines: () -> Void

    var body: some View {
        HStack {
            moreMenu
            Spacer()
            addMenu
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    private var addMenu: some View {
        Menu {
            if clients.isEmpty {
                Button { onIncome(nil) } label: {
                    MenuRowLabel("Income", glyph: "dollarsign")
                }
            } else {
                Menu {
                    ForEach(clients) { client in
                        Button { onIncome(client) } label: { Text(client.name) }
                    }
                } label: {
                    MenuRowLabel("Income", glyph: "dollarsign")
                }
            }
            Button(action: onNewClient) {
                MenuRowLabel("Client", glyph: "person.crop.circle.badge.plus")
            }
            Button(action: onNewHeading) {
                MenuRowLabel("Heading", glyph: "text.alignleft")
            }
            if !clients.isEmpty {
                Button(action: onPasteLines) {
                    MenuRowLabel("Paste lines", glyph: "doc.on.clipboard")
                }
            }
        } label: {
            toolbarMenuSymbol("plus", prominent: true)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.extraLarge)
        .tint(.primary)
        .accessibilityLabel("Add")
        .accessibilityIdentifier("ledger.fab")
    }

    private var moreMenu: some View {
        Menu {
            Button(action: onSearch) {
                MenuRowLabel("Search", glyph: "magnifyingglass")
            }
            Button(action: onInsights) {
                MenuRowLabel("Insights", glyph: "chart.bar")
            }
            Button(action: onPending) {
                MenuRowLabel(verbatim: pendingLabel, glyph: "clock")
            }
            Button(action: onSettings) {
                MenuRowLabel("Settings", glyph: "gearshape")
            }
        } label: {
            toolbarMenuSymbol("ellipsis")
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.extraLarge)
        .tint(.primary)
        .accessibilityLabel("More")
        .accessibilityValue(pendingLabel)
        .accessibilityIdentifier("ledger.menu")
    }

    private var pendingLabel: String {
        pendingCount > 0
            ? String(localized: "Pending (\(pendingCount))")
            : String(localized: "Pending")
    }

    private func toolbarMenuSymbol(_ systemName: String, prominent: Bool = false) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 19, weight: prominent ? .semibold : .medium))
            .symbolRenderingMode(.monochrome)
            .frame(width: 24, height: 24)
    }
}
