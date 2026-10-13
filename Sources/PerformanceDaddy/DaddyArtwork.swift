import AppKit
import SwiftUI

/// Original Daddy-series assets reused unchanged with the owner's approval.
struct DaddyArtwork: View {
    var brand = false
    var topic = 5
    private static let mark = DecodedArtwork.image(url: DaddyResources.url(forResource: "PerformanceDaddy"), maximumPixels: 128)
    private static let sheet = DecodedArtwork.image(url: DaddyResources.url(forResource: "PageDoodles"), maximumPixels: 432)
    var body: some View {
        GeometryReader { geometry in
            if brand, let image = Self.mark {
                Image(nsImage: image).resizable().scaledToFit()
            } else if let image = Self.sheet {
                Image(nsImage: image).resizable().interpolation(.high)
                    .frame(width: geometry.size.width * 3, height: geometry.size.height * 3)
                    .offset(x: -CGFloat(topic % 3) * geometry.size.width,
                            y: -CGFloat(topic / 3) * geometry.size.height)
            }
        }.clipped().allowsHitTesting(false).accessibilityHidden(true)
    }
}

private class DaddyResourceAnchor {}

enum DaddyResources {
    static func url(forResource nameForArtwork: String) -> URL? {
        let name = "PerformanceDaddy_PerformanceDaddy.bundle"
        var locations = [
            Bundle.main.resourceURL?.appendingPathComponent(name),
            Bundle(for: DaddyResourceAnchor.self).resourceURL?.appendingPathComponent(name),
            Bundle.main.bundleURL.appendingPathComponent(name),
            URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent(name)
        ]
        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["PACKAGE_RESOURCE_BUNDLE_PATH"]
            ?? ProcessInfo.processInfo.environment["PACKAGE_RESOURCE_BUNDLE_URL"] {
            locations.insert(URL(fileURLWithPath: path).appendingPathComponent(name), at: 0)
        }
        #endif
        return locations.compactMap { $0 }.compactMap { Bundle(url: $0) }
            .compactMap { $0.url(forResource: nameForArtwork, withExtension: "png") }.first
    }
}
