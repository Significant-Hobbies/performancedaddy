import SwiftUI

enum PerformanceTheme {
    // Daddy series: exact StorageDaddy Tints and app-owned black surfaces.
    static let fog = DaddyPalette.canvas
    static let surface = DaddyPalette.canvas
    static let ink = DaddyPalette.ink
    static let secondaryInk = DaddyPalette.secondaryInk
    static let coral = DaddyPalette.coral
    static let coralWash = coral.opacity(0.12)
    static let mintInk = DaddyPalette.mint
    static let mint = mintInk.opacity(0.18)
    static let action = mintInk
    static let blue = DaddyPalette.blue
    static let cyan = DaddyPalette.cyan
    static let amber = DaddyPalette.amber
    static let divider = secondaryInk.opacity(0.18)
}

/// Shared Daddy-series control pattern, copied from StorageButtonStyle.
struct DaddyButtonStyle: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        DaddyControlStyle(prominent: prominent, hoverFeedback: true)
            .makeBody(configuration: configuration)
    }
}

struct PrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        DaddyButtonStyle(prominent: true).makeBody(configuration: configuration)
    }
}
