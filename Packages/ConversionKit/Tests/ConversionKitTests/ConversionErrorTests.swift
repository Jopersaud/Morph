import Foundation
import Testing

@testable import ConversionKit

@Suite("Errors and options")
struct ConversionErrorTests {

    private static let samples: [ConversionError] = [
        .unsupported(ConversionRoute(source: FormatCatalog.heic, target: FormatCatalog.mp4)),
        .unreadable(URL(fileURLWithPath: "/tmp/photo.heic"), reason: "not downloaded"),
        .encoderUnavailable(FormatCatalog.avif),
        .diskFull(URL(fileURLWithPath: "/tmp/photo.jpg")),
        .destinationNotWritable(URL(fileURLWithPath: "/Library")),
        .cancelled,
        .engine("libwebp said no"),
    ]

    @Test("Every error has a human-readable message", arguments: Self.samples)
    func errorsAreReadable(error: ConversionError) {
        let message = error.errorDescription
        #expect(message?.isEmpty == false)
        // Messages are shown verbatim in the Jobs list, so they read as
        // sentences rather than enum cases.
        #expect(message?.contains("ConversionError") == false)
    }

    @Test("Unsupported routes name both formats")
    func unsupportedNamesFormats() {
        let route = ConversionRoute(source: FormatCatalog.heic, target: FormatCatalog.mp4)
        let message = ConversionError.unsupported(route).errorDescription ?? ""
        #expect(message.contains("HEIC"))
        #expect(message.contains("MP4"))
        #expect(route.description == "HEIC → MP4")
    }

    @Test("Options default per category", arguments: FileFormat.Category.allCases)
    func optionsDefaultPerCategory(category: FileFormat.Category) {
        #expect(ConversionOptions.default(for: category).category == category)
    }

    @Test("Image defaults keep metadata and the original size")
    func imageDefaults() {
        let options = ImageOptions()
        #expect(options.quality > 0 && options.quality <= 1)
        #expect(options.maxLongEdge == nil)
        #expect(options.stripMetadata == false)
        #expect(options.flattenBackground == "#FFFFFF")
    }
}
