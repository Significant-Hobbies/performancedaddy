import Foundation
import SaaSMakerUI
import Testing
@testable import PerformanceDaddy

struct PerformanceUIResourcesTests {
    @Test func missingBundleUsesFallback() {
        #expect(!PerformanceUIResources.registerFonts(in: nil))
    }

    @Test func incompleteAndCorruptFontsFailQualificationWithoutTrapping() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("performance-fonts-\(UUID().uuidString).bundle")
        let fonts = root.appendingPathComponent("Contents/Resources/Fonts")
        try FileManager.default.createDirectory(at: fonts, withIntermediateDirectories: true)
        let bundle = try #require(Bundle(url: root))
        #expect(!PerformanceUIResources.registerFonts(in: bundle))
        for name in SMFonts.files {
            try Data("invalid font".utf8).write(to: fonts.appendingPathComponent(name + ".ttf"))
        }
        #expect(!PerformanceUIResources.registerFonts(in: bundle))
    }
}
