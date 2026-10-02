import AppKit
import ImageIO

/// Decode PNGs at their actual display budget instead of retaining full-size
/// compressed sources and allowing every SwiftUI use to request another size.
@MainActor
enum DecodedArtwork {
    static func image(url: URL?, maximumPixels: Int) -> NSImage? {
        guard let url, maximumPixels > 0,
              let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixels,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}
