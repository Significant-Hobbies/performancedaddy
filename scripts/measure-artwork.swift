import AppKit
import Darwin

@main struct ArtworkProbe {
    @MainActor static func main() throws {
        let mode = CommandLine.arguments[1]
        let root = URL(fileURLWithPath: CommandLine.arguments[2])
        var retained: [NSImage] = []
        var decodedBytes = 0
        var pixelChecksum: UInt64 = 0
        for (name, pixels) in [("PerformanceDaddy", 128), ("PerformanceDaddy", 256), ("PageDoodles", 432)] {
            let url = root.appendingPathComponent(name + ".png")
            guard let image = mode == "original" ? NSImage(contentsOf: url) : DecodedArtwork.image(url: url, maximumPixels: pixels),
                  let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { fatalError("Asset unavailable") }
            // Force decoded pixels to be touched; retain the same three uses.
            guard let data = cg.dataProvider?.data else { fatalError("No pixels") }
            let bytes = CFDataGetBytePtr(data)!
            var checksum: UInt64 = 0
            for i in stride(from: 0, to: CFDataGetLength(data), by: 4096) { checksum += UInt64(bytes[i]) }
            decodedBytes += cg.bytesPerRow * cg.height
            retained.append(image)
            pixelChecksum += checksum
        }
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        precondition(status == KERN_SUCCESS)
        withExtendedLifetime(retained) {
            print("{\"mode\":\"\(mode)\",\"decodedBytes\":\(decodedBytes),\"physicalFootprintBytes\":\(info.phys_footprint),\"pixelChecksum\":\(pixelChecksum)}")
        }
    }
}
