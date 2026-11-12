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
        var palette = SMPalette.ink.dark.brand(
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
        palette.radius = 10
        palette.displayFont = palette.sansFont
        palette.input = divider
        palette.displayWeight = 600
        palette.displayTracking = -0.025
        return palette
    }()
}

extension View {
    /// Use packaged fonts when available; missing optional fonts must not trap.
    func performanceTheme(_ palette: SMPalette) -> some View {
        _ = PerformanceUIResources.loaded
        return environment(\.smPalette, palette)
            .tint(palette.brand)
            .foregroundStyle(palette.foreground)
            .font(.custom(palette.sansFont, size: 14, relativeTo: .body))
            .background(palette.background.ignoresSafeArea())
            .preferredColorScheme(palette.isDark ? .dark : .light)
    }
}

/// Product page introductions keep the measured evidence underneath compact.
struct PerformancePageHeader: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(PerformanceTheme.mintInk)
                .frame(width: 42, height: 42)
                .background(PerformanceTheme.palette.brandSoft, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 5) {
                SMSectionHeader(title, size: 26)
                    .accessibilityLabel(title).accessibilityAddTraits(.isHeader)
                Text(subtitle).font(.callout)
                    .foregroundStyle(PerformanceTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}
