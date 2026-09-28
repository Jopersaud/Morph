import Foundation
import Testing

@testable import ConversionKit

// MARK: - Stubs

/// Stands in for a native engine: HEIC → JPG, PNG.
private struct NativeStub: Converter {
    static let id = "test.native"
    static let routes: [FileFormat: [FileFormat]] = [
        FormatCatalog.heic: [FormatCatalog.jpeg, FormatCatalog.png]
    ]
    func convert(_ job: ConversionJob, progress: @Sendable (Double) -> Void) async throws -> URL {
        progress(1)
        return job.destination
    }
}

/// Stands in for a bundled library covering the same route plus WebP.
private struct BundledStub: Converter {
    static let id = "test.bundled"
    static let priority = ConverterPriority.bundled
    static let routes: [FileFormat: [FileFormat]] = [
        FormatCatalog.heic: [FormatCatalog.jpeg, FormatCatalog.webp]
    ]
    func convert(_ job: ConversionJob, progress: @Sendable (Double) -> Void) async throws -> URL {
        progress(1)
        return job.destination
    }
}

/// A converter this Mac can't run.
private struct UnavailableStub: Converter {
    static let id = "test.unavailable"
    static let routes: [FileFormat: [FileFormat]] = [
        FormatCatalog.svg: [FormatCatalog.pdf]
    ]
    static func isAvailable() -> Bool { false }
    func convert(_ job: ConversionJob, progress: @Sendable (Double) -> Void) async throws -> URL {
        throw ConversionError.encoderUnavailable(job.target)
    }
}

private struct TiffStub: Converter {
    static let id = "test.tiff"
    static let routes: [FileFormat: [FileFormat]] = [
        FormatCatalog.tiff: [FormatCatalog.jpeg]
    ]
    func convert(_ job: ConversionJob, progress: @Sendable (Double) -> Void) async throws -> URL {
        progress(1)
        return job.destination
    }
}

// MARK: - Tests

@Suite("Converter registry")
struct ConverterRegistryTests {

    @Test("An empty registry offers nothing")
    func emptyRegistry() {
        let registry = ConverterRegistry()
        #expect(registry.registeredIDs.isEmpty)
        #expect(registry.advertisedRoutes.isEmpty)
        #expect(registry.targets(for: FormatCatalog.heic).isEmpty)
        #expect(!registry.canConvert(from: FormatCatalog.heic, to: FormatCatalog.jpeg))
        #expect(registry.converter(from: FormatCatalog.heic, to: FormatCatalog.jpeg) == nil)
    }

    @Test("Targets are the union of the registered routes, in catalog order")
    func targetsAreUnioned() {
        var registry = ConverterRegistry()
        registry.register(BundledStub.self)
        registry.register(NativeStub.self)

        #expect(
            registry.targets(for: FormatCatalog.heic) == [
                FormatCatalog.jpeg, FormatCatalog.png, FormatCatalog.webp,
            ])
        #expect(registry.targets(for: FormatCatalog.mp4).isEmpty)
    }

    @Test("Native converters win over bundled ones whatever the order")
    func nativeBeatsBundled() {
        var bundledFirst = ConverterRegistry()
        bundledFirst.register(BundledStub.self)
        bundledFirst.register(NativeStub.self)

        var nativeFirst = ConverterRegistry()
        nativeFirst.register(NativeStub.self)
        nativeFirst.register(BundledStub.self)

        for registry in [bundledFirst, nativeFirst] {
            let chosen = registry.converterType(from: FormatCatalog.heic, to: FormatCatalog.jpeg)
            #expect(chosen?.id == NativeStub.id)
        }

        // Only the bundled stub covers WebP, so it still gets used.
        #expect(
            nativeFirst.converterType(from: FormatCatalog.heic, to: FormatCatalog.webp)?.id
                == BundledStub.id)
    }

    @Test("Registering the same id twice is a no-op")
    func duplicateRegistrationIgnored() {
        var registry = ConverterRegistry()
        registry.register(NativeStub.self)
        registry.register(NativeStub.self)
        #expect(registry.registeredIDs == [NativeStub.id])
    }

    @Test("Unavailable converters are advertised but never chosen")
    func unavailableConvertersAreHidden() {
        var registry = ConverterRegistry()
        registry.register(UnavailableStub.self)

        #expect(registry.registeredIDs == [UnavailableStub.id])
        #expect(registry.targets(for: FormatCatalog.svg).isEmpty)
        #expect(registry.converter(from: FormatCatalog.svg, to: FormatCatalog.pdf) == nil)
        #expect(registry.availableRoutes.isEmpty)
        #expect(
            registry.advertisedRoutes
                == [ConversionRoute(source: FormatCatalog.svg, target: FormatCatalog.pdf)])
    }

    @Test("A multi-file selection offers only the targets every file supports")
    func commonTargetsIntersect() {
        var registry = ConverterRegistry()
        registry.register(NativeStub.self)
        registry.register(TiffStub.self)

        #expect(
            registry.commonTargets(for: [FormatCatalog.heic, FormatCatalog.tiff])
                == [FormatCatalog.jpeg])
        #expect(registry.commonTargets(for: []).isEmpty)
        #expect(
            registry.commonTargets(for: [FormatCatalog.heic])
                == [FormatCatalog.jpeg, FormatCatalog.png])
        // Nothing handles MP4, so the intersection collapses.
        #expect(registry.commonTargets(for: [FormatCatalog.heic, FormatCatalog.mp4]).isEmpty)
    }

    @Test("The chosen converter runs")
    func chosenConverterRuns() async throws {
        var registry = ConverterRegistry()
        registry.register(NativeStub.self)

        let converter = try #require(
            registry.converter(from: FormatCatalog.heic, to: FormatCatalog.jpeg))
        let job = ConversionJob(
            source: URL(fileURLWithPath: "/tmp/photo.heic"),
            target: FormatCatalog.jpeg,
            options: .default(for: .image),
            destination: URL(fileURLWithPath: "/tmp/photo.jpg")
        )

        let output = try await converter.convert(job) { _ in }
        #expect(output == job.destination)
    }

    @Test("Every advertised route resolves to a converter")
    func advertisedRoutesResolve() {
        var registry = ConverterRegistry()
        registry.register(NativeStub.self)
        registry.register(BundledStub.self)
        registry.register(TiffStub.self)

        for route in registry.availableRoutes {
            #expect(
                registry.converterType(from: route.source, to: route.target) != nil,
                "no converter for \(route)")
        }
    }
}
