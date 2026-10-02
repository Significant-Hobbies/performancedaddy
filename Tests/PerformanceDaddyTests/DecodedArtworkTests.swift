import AppKit
@testable import PerformanceDaddy
import XCTest

@MainActor
final class DecodedArtworkTests: XCTestCase {
    func testOriginalAssetsDecodeWithinDisplayBudgets() throws {
        var total = 0
        for (name, pixels) in [("PerformanceDaddy", 128), ("PerformanceDaddy", 256), ("PageDoodles", 432)] {
            let image = try XCTUnwrap(DecodedArtwork.image(url: DaddyResources.url(forResource: name), maximumPixels: pixels))
            let cg = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
            XCTAssertLessThanOrEqual(cg.width, pixels)
            XCTAssertLessThanOrEqual(cg.height, pixels)
            total += cg.bytesPerRow * cg.height
        }
        XCTAssertLessThan(total, 1_100_000)
        // Previously: two 1254-square marks plus one 1000-square sheet,
        // at least 16.58 MB at RGBA8, before framework/decoder allocations.
        XCTAssertLessThan(Double(total) / Double((1254 * 1254 * 2 + 1000 * 1000) * 4), 0.07)
    }

    func testInvalidArtworkDoesNotAllocateOrInventAnImage() {
        XCTAssertNil(DecodedArtwork.image(url: nil, maximumPixels: 256))
        XCTAssertNil(DecodedArtwork.image(url: DaddyResources.url(forResource: "PageDoodles"), maximumPixels: 0))
    }
}
