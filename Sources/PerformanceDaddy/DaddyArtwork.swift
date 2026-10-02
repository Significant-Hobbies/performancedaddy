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

enum DaddyResources {
    static func url(forResource name: String) -> URL? {
        let packaged = Bundle.main.resourceURL.flatMap {
            Bundle(url: $0.appendingPathComponent("PerformanceDaddy_PerformanceDaddy.bundle"))
        }
        return packaged?.url(forResource: name, withExtension: "png")
            ?? Bundle.module.url(forResource: name, withExtension: "png")
    }
}
