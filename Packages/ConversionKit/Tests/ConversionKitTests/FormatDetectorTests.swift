import Foundation
import Testing

@testable import ConversionKit

@Suite("Format detection")
struct FormatDetectorTests {

    struct Case: Sendable, CustomTestStringConvertible {
        let bytes: [UInt8]
        let expected: FileFormat
        var testDescription: String { expected.displayName }
    }

    static let signatures: [Case] = [
        Case(bytes: Signatures.jpeg, expected: FormatCatalog.jpeg),
        Case(bytes: Signatures.png, expected: FormatCatalog.png),
        Case(bytes: Signatures.gif, expected: FormatCatalog.gif),
        Case(bytes: Signatures.tiffLittle, expected: FormatCatalog.tiff),
        Case(bytes: Signatures.tiffBig, expected: FormatCatalog.tiff),
        Case(bytes: Signatures.webp, expected: FormatCatalog.webp),
        Case(bytes: Signatures.pdf, expected: FormatCatalog.pdf),
        Case(bytes: Signatures.bmp, expected: FormatCatalog.bmp),
        Case(bytes: Signatures.heic, expected: FormatCatalog.heic),
        Case(bytes: Signatures.heifMif1, expected: FormatCatalog.heic),
        Case(bytes: Signatures.avif, expected: FormatCatalog.avif),
        Case(bytes: Signatures.avifUnderMif1, expected: FormatCatalog.avif),
    ]

    @Test("Signatures identify the format", arguments: Self.signatures)
    func sniffsSignatures(sample: Case) {
        #expect(FormatDetector.sniff(Data(sample.bytes)) == sample.expected)
    }

    @Test("Content beats the extension")
    func contentWinsOverExtension() throws {
        let folder = try TemporaryFolder()
        let mislabeled = try folder.write("actually-a-png.jpg", bytes: Signatures.png)
        #expect(try FormatDetector.detect(mislabeled) == FormatCatalog.png)
    }

    @Test("Movie containers fall back to the system type")
    func moviesUseTheSystemType() throws {
        #expect(FormatDetector.sniff(Data(Signatures.mp4)) == nil)
        let folder = try TemporaryFolder()
        let movie = try folder.write("clip.mp4", bytes: Signatures.mp4)
        #expect(try FormatDetector.detect(movie) == FormatCatalog.mp4)
    }

    @Test("Text that starts with BM isn't a bitmap")
    func weakBitmapSignatureIsRejected() {
        #expect(FormatDetector.sniff(Data("BMW owners' notes, part one".utf8)) == nil)
    }

    @Test("Formats without a signature use the system type")
    func plainTextUsesTheSystemType() throws {
        let folder = try TemporaryFolder()
        let notes = try folder.write("notes.txt", bytes: Array("hello, world\n".utf8))
        #expect(try FormatDetector.detect(notes) == FormatCatalog.txt)
    }

    @Test("Unknown content with no extension is reported, not guessed")
    func unknownFormat() throws {
        let folder = try TemporaryFolder()
        let blob = try folder.write("blob", bytes: [0x00, 0x01, 0x02, 0x03, 0x04])
        #expect(throws: ConversionError.unknownFormat(blob)) {
            try FormatDetector.detect(blob)
        }
    }

    @Test("Missing files, folders and empty files are unreadable")
    func unreadableInputs() throws {
        let folder = try TemporaryFolder()
        let missing = folder.url.appendingPathComponent("gone.png")
        let empty = try folder.write("empty.png", bytes: [])

        for url in [missing, folder.url, empty] {
            #expect {
                try FormatDetector.detect(url)
            } throws: { error in
                guard case .unreadable(let failing, _) = error as? ConversionError else {
                    return false
                }
                return failing.standardizedFileURL == url.standardizedFileURL
            }
        }
    }
}
