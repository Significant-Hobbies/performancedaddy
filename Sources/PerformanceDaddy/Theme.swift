import SwiftUI
import SaaSMakerUI

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

    /// Library roles with Daddy surfaces and measured-evidence semantics.
    static let palette: SMPalette = {
        var palette = SMPalette.ink.brand(
            Color(.sRGB, red: 107 / 255, green: 201 / 255, blue: 158 / 255, opacity: 1),
            foreground: .black)
        palette.background = fog
        palette.surface = surface
        palette.card = surface
        palette.foreground = ink
        palette.mutedForeground = secondaryInk
        palette.border = divider
        palette.hairline = divider
        palette.success = mintInk
        palette.warning = amber
        palette.destructive = coral
        palette.accent = mintInk.opacity(0.11)
        palette.radius = 8
        palette.displayWeight = 600
        palette.displayTracking = -0.025
        return palette
    }()
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
