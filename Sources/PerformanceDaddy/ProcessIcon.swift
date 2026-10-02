import AppKit
import PerformanceCore
import SwiftUI

/// Adapted from StorageDaddy's native application-icon pattern. Icons are
/// cached by owning bundle, never fetched once per PID or on every sample.
@MainActor
enum ProcessIconCache {
    static let images: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 160
        cache.totalCostLimit = 2 * 1024 * 1024
        return cache
    }()

    static func icon(for executable: String) -> NSImage? {
        let components = NSString(string: executable).pathComponents
        guard let index = components.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
        let path = NSString.path(withComponents: Array(components.prefix(index + 1)))
        return icon(forAppPath: path)
    }

    static func icon(forAppPath path: String) -> NSImage? {
        if let cached = images.object(forKey: path as NSString) { return cached }
        let source = NSWorkspace.shared.icon(forFile: path)
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64,
                                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                           isPlanar: false, colorSpaceName: .deviceRGB,
                                           bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let target = NSRect(x: 0, y: 0, width: 64, height: 64)
        if let representation = source.bestRepresentation(for: target, context: context, hints: nil) {
            representation.draw(in: target)
        } else {
            source.draw(in: target, from: .zero, operation: .copy, fraction: 1)
        }
        NSGraphicsContext.restoreGraphicsState()
        let icon = NSImage(size: NSSize(width: 32, height: 32))
        icon.addRepresentation(bitmap)
        images.setObject(icon, forKey: path as NSString, cost: bitmap.bytesPerRow * bitmap.pixelsHigh)
        return icon
    }
}

struct AppBundleIcon: View {
    let path: String
    let size: CGFloat

    var body: some View {
        Group {
            if let icon = ProcessIconCache.icon(forAppPath: path) {
                Image(nsImage: icon).resizable().scaledToFit()
            } else {
                Image(systemName: "app")
                    .foregroundStyle(PerformanceTheme.secondaryInk)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct ProcessIcon: View {
    let process: LiveProcess

    var body: some View {
        Group {
            if process.id.pid == ProcessInfo.processInfo.processIdentifier, let icon = PerformanceAppIcon.image {
                Image(nsImage: icon).resizable().scaledToFit()
            } else if let icon = ProcessIconCache.icon(for: process.executable) {
                Image(nsImage: icon).resizable().scaledToFit()
            } else {
                Text(String(process.sortName.prefix(2)).uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(PerformanceTheme.secondaryInk)
                    .frame(width: 28, height: 28)
                    .background(PerformanceTheme.mintInk.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
            }
        }.frame(width: 28, height: 28).accessibilityHidden(true)
    }
}
