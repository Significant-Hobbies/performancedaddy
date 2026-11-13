import SwiftUI
import SaaSMakerUI

enum PerformanceTheme {
    // Daddy series: exact StorageDaddy Tints and app-owned black surfaces.
    static let fog = DaddyPalette.canvas
    static let surface = DaddyPalette.canvas
    static let ink = Color(red: 0.94, green: 0.96, blue: 0.95)
    static let secondaryInk = Color(red: 0.59, green: 0.64, blue: 0.61)
    static let coral = DaddyPalette.coral
    static let coralWash = coral.opacity(0.12)
    static let mintInk = DaddyPalette.mint
    static let mint = mintInk.opacity(0.18)
    static let action = mintInk
    static let blue = DaddyPalette.blue
    static let cyan = DaddyPalette.cyan
    static let amber = DaddyPalette.amber
    static let divider = Color.white.opacity(0.10)

    /// Library roles with Daddy surfaces and measured-evidence semantics.
    static let palette: SMPalette = {
        var palette = SMPalette.ink.dark.brand(
            Color(.sRGB, red: 107 / 255, green: 201 / 255, blue: 158 / 255, opacity: 1),
            foreground: .black)
        palette.background = fog
        palette.surface = Color(red: 0.025, green: 0.032, blue: 0.028)
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
        palette.displayFont = "Figtree"
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
struct PerformancePageHeader<Actions: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    let showsArtwork: Bool
    private let actions: Actions

    init(title: String, subtitle: String, icon: String, showsArtwork: Bool = true, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.showsArtwork = showsArtwork
        self.actions = actions()
    }

    var body: some View {
        SMWorkspaceHeader(title, subtitle: subtitle) {
            HStack(spacing: 10) {
                actions
                if showsArtwork {
                    DaddyArtwork(topic: artworkTopic).frame(width: 64, height: 64)
                }
            }
        }
    }

    private var artworkTopic: Int {
        switch icon {
        case "network": 3
        case "memorychip": 5
        case "terminal": 8
        case "doc.text.magnifyingglass": 1
        case "lock.shield": 2
        default: 0
        }
    }
}

extension PerformancePageHeader where Actions == EmptyView {
    init(title: String, subtitle: String, icon: String) {
        self.init(title: title, subtitle: subtitle, icon: icon) { EmptyView() }
    }
}
