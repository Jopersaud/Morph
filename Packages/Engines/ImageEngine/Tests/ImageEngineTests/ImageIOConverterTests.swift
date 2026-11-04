import ConversionKit
import Foundation
import ImageIO
import Testing

@testable import ImageEngine

@Suite("ImageIO converter")
struct ImageIOConverterTests {

    /// Every route the converter advertises, so a new route without a fixture
    /// fails here rather than slipping through (SPEC §11).
    static let routes = ImageIOConverter.routePairs.sorted { $0.description < $1.description }

    private func convert(
        _ source: URL,
        to target: FileFormat,
        options: ImageOptions = ImageOptions(),
        in folder: TemporaryFolder
    ) async throws -> URL {
        let job = ConversionJob(
            source: source,
            target: target,
            options: .image(options),
            destination: folder.file("output.\(target.preferredExtension)"))
        return try await ImageIOConverter().convert(job) { _ in }
    }

    @Test("M1 covers JPEG, PNG, HEIC, TIFF and BMP in every direction")
    func routeCoverage() {
        // The CI Macs and every Apple-silicon Mac can read and write all five.
        #expect(ImageIOConverter.isAvailable())
        #expect(Self.routes.count == 20)
        #expect(Set(ImageIOConverter.routes.keys) == Set(ImageIOConverter.formats))
    }

    @Test("Every route converts its fixture", arguments: Self.routes)
    func everyRoute(route: ConversionRoute) async throws {
        let folder = try TemporaryFolder()
        let fixture = Fixtures.image(route.source)
        try #require(
            FileManager.default.fileExists(atPath: fixture.path), "no fixture for \(route.source)")

        let output = try await convert(fixture, to: route.target, in: folder)

        let decoded = try DecodedImage(output)
        #expect(decoded.typeIdentifier == route.target.utType.identifier)
        #expect(decoded.width == Fixtures.width)
        #expect(decoded.height == Fixtures.height)
        #expect(try FormatDetector.detect(output) == route.target)
    }

    @Test("Metadata is kept by default")
    func keepsMetadata() async throws {
        let folder = try TemporaryFolder()
        let output = try await convert(
            Fixtures.image(FormatCatalog.heic), to: FormatCatalog.jpeg, in: folder)

        let decoded = try DecodedImage(output)
        #expect(decoded.gps?[kCGImagePropertyGPSLatitude] as? Double == 43.0389)
        #expect(decoded.tiff?[kCGImagePropertyTIFFModel] as? String == "Fixture Camera")
        #expect(
            decoded.exif?[kCGImagePropertyExifDateTimeOriginal] as? String == "2026:01:02 03:04:05")
    }

    @Test("Stripping removes location and camera data but keeps the date")
    func stripsMetadata() async throws {
        let folder = try TemporaryFolder()
        let output = try await convert(
            Fixtures.image(FormatCatalog.heic), to: FormatCatalog.jpeg,
            options: ImageOptions(stripMetadata: true), in: folder)

        let decoded = try DecodedImage(output)
        #expect(decoded.gps == nil)
        #expect(decoded.tiff?[kCGImagePropertyTIFFMake] == nil)
        #expect(decoded.tiff?[kCGImagePropertyTIFFModel] == nil)
        #expect(decoded.exif?[kCGImagePropertyExifLensModel] == nil)
        #expect(
            decoded.exif?[kCGImagePropertyExifDateTimeOriginal] as? String == "2026:01:02 03:04:05")
    }

    @Test("A max long edge scales down and keeps the aspect ratio")
    func resizes() async throws {
        let folder = try TemporaryFolder()
        let output = try await convert(
            Fixtures.image(FormatCatalog.png), to: FormatCatalog.jpeg,
            options: ImageOptions(maxLongEdge: 32), in: folder)

        let decoded = try DecodedImage(output)
        #expect(decoded.width == 32)
        #expect(decoded.height == 24)
    }

    @Test("A max long edge never scales up")
    func neverUpscales() async throws {
        let folder = try TemporaryFolder()
        let output = try await convert(
            Fixtures.image(FormatCatalog.png), to: FormatCatalog.tiff,
            options: ImageOptions(maxLongEdge: 4_000), in: folder)

        let decoded = try DecodedImage(output)
        #expect(decoded.width == Fixtures.width)
        #expect(decoded.height == Fixtures.height)
    }

    @Test("Transparency flattens onto the background colour for JPEG")
    func flattensTransparency() async throws {
        let folder = try TemporaryFolder()
        let white = try await convert(Fixtures.transparentPNG, to: FormatCatalog.jpeg, in: folder)
        let corner = try DecodedImage(white).rgba(x: 2, y: 2)
        #expect(corner[0] > 245 && corner[1] > 245 && corner[2] > 245, "corner was \(corner)")

        let blackFolder = try TemporaryFolder()
        let black = try await convert(
            Fixtures.transparentPNG, to: FormatCatalog.jpeg,
            options: ImageOptions(flattenBackground: "#000000"), in: blackFolder)
        let decoded = try DecodedImage(black)
        let blackCorner = decoded.rgba(x: 2, y: 2)
        #expect(blackCorner[0] < 10 && blackCorner[1] < 10 && blackCorner[2] < 10)
        // The opaque red middle survives either way.
        let middle = decoded.rgba(x: 32, y: 24)
        #expect(middle[0] > 200 && middle[1] < 60 && middle[2] < 60, "middle was \(middle)")
    }

    @Test("Transparency survives into formats that have an alpha channel")
    func keepsTransparency() async throws {
        let folder = try TemporaryFolder()
        let output = try await convert(Fixtures.transparentPNG, to: FormatCatalog.tiff, in: folder)
        #expect(try DecodedImage(output).rgba(x: 2, y: 2)[3] == 0)
    }

    @Test("BMP output is rotated upright, since BMP can't record orientation")
    func bakesOrientationForBMP() async throws {
        let folder = try TemporaryFolder()
        let rotated = folder.file("rotated.jpg")
        try writeRotatedJPEG(to: rotated)

        let output = try await convert(rotated, to: FormatCatalog.bmp, in: folder)

        let decoded = try DecodedImage(output)
        #expect(decoded.width == Fixtures.height)
        #expect(decoded.height == Fixtures.width)
    }

    @Test("Other outputs keep the orientation flag instead of rotating pixels")
    func keepsOrientationFlag() async throws {
        let folder = try TemporaryFolder()
        let rotated = folder.file("rotated.jpg")
        try writeRotatedJPEG(to: rotated)

        let output = try await convert(rotated, to: FormatCatalog.png, in: folder)

        let decoded = try DecodedImage(output)
        #expect(decoded.properties[kCGImagePropertyOrientation] as? Int == 6)
        #expect(decoded.width == Fixtures.width)
    }

    @Test("A damaged image is reported as unreadable")
    func damagedImage() async throws {
        let folder = try TemporaryFolder()
        let damaged = folder.file("damaged.heic")
        let fixture = try Data(contentsOf: Fixtures.image(FormatCatalog.heic))
        try fixture.prefix(40).write(to: damaged)

        await #expect {
            _ = try await convert(damaged, to: FormatCatalog.jpeg, in: folder)
        } throws: { error in
            if case .unreadable = error as? ConversionError { true } else { false }
        }
    }

    @Test("Background colours parse, and nonsense falls back to white")
    func backgroundColours() {
        #expect(ImageIOConverter.color(hex: "#FF0000").components == [1, 0, 0, 1])
        #expect(ImageIOConverter.color(hex: "00FF00").components == [0, 1, 0, 1])
        #expect(ImageIOConverter.color(hex: "orange").components == [1, 1, 1, 1])
    }
}
