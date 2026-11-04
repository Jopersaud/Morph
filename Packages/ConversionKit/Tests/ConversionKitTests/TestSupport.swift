import Foundation

/// A fresh folder under the temp directory, deleted when the test is done
/// with it.
final class TemporaryFolder {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MorphTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        // A read-only folder from a test can't be emptied until it's writable.
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        try? FileManager.default.removeItem(at: url)
    }

    @discardableResult
    func write(_ name: String, bytes: [UInt8] = Signatures.png) throws -> URL {
        let file = url.appendingPathComponent(name, isDirectory: false)
        try Data(bytes).write(to: file)
        return file
    }

    func names() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: url.path).sorted()
    }
}

/// Leading bytes for the formats the detector recognises by content.
enum Signatures {
    static let png: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + padding
    static let jpeg: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE0] + padding
    static let gif: [UInt8] = Array("GIF89a".utf8) + padding
    static let tiffLittle: [UInt8] = [0x49, 0x49, 0x2A, 0x00] + padding
    static let tiffBig: [UInt8] = [0x4D, 0x4D, 0x00, 0x2A] + padding
    static let webp: [UInt8] = Array("RIFF".utf8) + [0, 0, 0, 0] + Array("WEBP".utf8) + padding
    static let pdf: [UInt8] = Array("%PDF-1.7\n".utf8) + padding
    static let bmp: [UInt8] =
        [0x42, 0x4D] + [UInt8](repeating: 0, count: 12) + [40, 0, 0, 0] + padding
    static let heic = ftyp(major: "heic", compatible: ["mif1", "heic"])
    static let heifMif1 = ftyp(major: "mif1", compatible: ["mif1", "miaf"])
    static let avif = ftyp(major: "avif", compatible: ["mif1", "avif"])
    static let avifUnderMif1 = ftyp(major: "mif1", compatible: ["avif", "mif1", "miaf"])
    static let mp4 = ftyp(major: "isom", compatible: ["isom", "iso2", "mp41"])

    static let padding = [UInt8](repeating: 0, count: 32)

    static func ftyp(major: String, compatible: [String]) -> [UInt8] {
        let body = Array(major.utf8) + [0, 0, 0, 0] + compatible.flatMap { Array($0.utf8) }
        let size = UInt32(8 + body.count)
        let sizeBytes = withUnsafeBytes(of: size.bigEndian) { Array($0) }
        return sizeBytes + Array("ftyp".utf8) + body + padding
    }
}
