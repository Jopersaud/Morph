import Foundation
import UniformTypeIdentifiers

/// Works out what a file really is (SPEC §6).
///
/// Content wins over the name: a format with a recognisable signature is
/// identified by its first bytes, so a PNG saved as `photo.jpg` is treated as
/// a PNG. Formats without one fall back to the type macOS reports for the file.
public enum FormatDetector {

    /// How many leading bytes the signature checks look at.
    static let headerLength = 64

    public static func detect(_ url: URL) throws -> FileFormat {
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [
                .isDirectoryKey, .contentTypeKey, .isUbiquitousItemKey,
                .ubiquitousItemDownloadingStatusKey,
            ])
        } catch {
            throw ConversionError.unreadable(url, reason: "the file couldn't be found.")
        }

        if values.isDirectory == true {
            throw ConversionError.unreadable(url, reason: "it's a folder.")
        }
        if values.isUbiquitousItem == true,
            values.ubiquitousItemDownloadingStatus == .notDownloaded
        {
            throw ConversionError.unreadable(
                url, reason: "it hasn't finished downloading from iCloud Drive.")
        }

        let header = try readHeader(of: url)
        if let format = sniff(header) {
            return format
        }
        if let type = values.contentType, let format = FormatCatalog.format(matching: type) {
            return format
        }
        throw ConversionError.unknownFormat(url)
    }

    static func readHeader(of url: URL) throws -> Data {
        let header: Data?
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            header = try handle.read(upToCount: headerLength)
        } catch {
            throw ConversionError.unreadable(
                url, reason: "Morph doesn't have permission to open it.")
        }
        guard let header, !header.isEmpty else {
            throw ConversionError.unreadable(url, reason: "the file is empty.")
        }
        return header
    }

    /// Identifies a format from its leading bytes, or returns `nil` when the
    /// bytes don't settle it.
    static func sniff(_ header: Data) -> FileFormat? {
        let bytes = [UInt8](header.prefix(headerLength))

        func starts(with signature: [UInt8], at offset: Int = 0) -> Bool {
            bytes.count >= offset + signature.count
                && Array(bytes[offset..<offset + signature.count]) == signature
        }
        func ascii(_ string: String, at offset: Int = 0) -> Bool {
            starts(with: Array(string.utf8), at: offset)
        }

        if starts(with: [0xFF, 0xD8, 0xFF]) { return FormatCatalog.jpeg }
        if starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
            return FormatCatalog.png
        }
        if ascii("GIF87a") || ascii("GIF89a") { return FormatCatalog.gif }
        if starts(with: [0x49, 0x49, 0x2A, 0x00]) || starts(with: [0x4D, 0x4D, 0x00, 0x2A]) {
            return FormatCatalog.tiff
        }
        if ascii("RIFF") && ascii("WEBP", at: 8) { return FormatCatalog.webp }
        if ascii("%PDF-") { return FormatCatalog.pdf }
        if isBMP(bytes) { return FormatCatalog.bmp }
        if ascii("ftyp", at: 4) { return isoMediaFormat(bytes) }
        return nil
    }

    /// "BM" alone is too weak a signature for text files that happen to start
    /// with it, so also require a DIB header size Windows actually writes.
    private static func isBMP(_ bytes: [UInt8]) -> Bool {
        guard bytes.count >= 18, bytes[0] == 0x42, bytes[1] == 0x4D else { return false }
        let dibSize =
            Int(bytes[14]) | Int(bytes[15]) << 8 | Int(bytes[16]) << 16 | Int(bytes[17]) << 24
        return [12, 40, 52, 56, 64, 108, 124].contains(dibSize)
    }

    /// HEIF and AVIF share the ISO base media container with MP4 and MOV; the
    /// brands in the `ftyp` box tell them apart. Movie brands return `nil` and
    /// fall back to the system type, which knows MP4 from MOV from M4A.
    private static func isoMediaFormat(_ bytes: [UInt8]) -> FileFormat? {
        guard bytes.count >= 12 else { return nil }
        let boxSize = Int(bytes[0]) << 24 | Int(bytes[1]) << 16 | Int(bytes[2]) << 8 | Int(bytes[3])
        let end = min(bytes.count, max(boxSize, 12))

        // The major brand, then the compatible brands after the minor version.
        var brands = [String(decoding: bytes[8..<12], as: UTF8.self)]
        var offset = 16
        while offset + 4 <= end {
            brands.append(String(decoding: bytes[offset..<offset + 4], as: UTF8.self))
            offset += 4
        }

        if brands.contains(where: { $0 == "avif" || $0 == "avis" }) {
            return FormatCatalog.avif
        }
        let heifBrands: Set = ["heic", "heix", "hevc", "hevx", "heim", "heis", "mif1", "msf1"]
        if brands.contains(where: heifBrands.contains) {
            return FormatCatalog.heic
        }
        return nil
    }
}
