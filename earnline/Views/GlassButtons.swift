import SwiftUI

/// The compact circular Liquid-Glass "+" used on client chips.
struct GlassCircleButton: View {
    var systemName: String = "plus"
    var size: CGFloat = 15
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(Theme.label)
                .frame(width: 28, height: 28)
                .contentShape(.circle)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
    }
}
