import Foundation

/// How much Morph would rather use a converter, when several can do the same
/// route. Apple frameworks come first, bundled libraries second (SPEC §6).
public enum ConverterPriority: Int, Comparable, Sendable, CaseIterable {
    /// Built into macOS: ImageIO, AVFoundation, PDFKit, the AppKit text system.
    case native = 0
    /// A library Morph bundles: FFmpeg, libwebp, libavif, resvg, libarchive.
    case bundled = 100

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// One conversion strategy.
///
/// A converter is a value type with no stored state: the registry makes one on
/// demand, so `convert` must be safe to call from any task.
public protocol Converter: Sendable {
    static var id: String { get }

    /// Input formats this converter accepts, with the targets it can produce
    /// from each.
    static var routes: [FileFormat: [FileFormat]] { get }

    static var priority: ConverterPriority { get }

    /// Whether this converter can run on *this* Mac, checked at runtime.
    ///
    /// Encoder availability varies by OS version and hardware, so ask the
    /// framework (`CGImageDestinationCopyTypeIdentifiers()`, an
    /// `AVAssetWriter` probe) rather than assuming.
    static func isAvailable() -> Bool

    init()

    func convert(
        _ job: ConversionJob,
        progress: @Sendable (Double) -> Void
    ) async throws -> URL
}

extension Converter {
    public static var priority: ConverterPriority { .native }
    public static func isAvailable() -> Bool { true }

    /// Flat list of the (source, target) pairs this converter advertises.
    public static var routePairs: [ConversionRoute] {
        routes.flatMap { source, targets in
            targets.map { ConversionRoute(source: source, target: $0) }
        }
    }
}

/// A single (source → target) pair.
public struct ConversionRoute: Hashable, Sendable {
    public let source: FileFormat
    public let target: FileFormat

    public init(source: FileFormat, target: FileFormat) {
        self.source = source
        self.target = target
    }
}

extension ConversionRoute: CustomStringConvertible {
    public var description: String { "\(source.displayName) → \(target.displayName)" }
}

/// A group of converters shipped as one package (`ImageEngine`, `MediaEngine`,
/// …). Engines exist so the app can register everything at once and the Finder
/// extension can register nothing at all.
public protocol EngineModule: Sendable {
    static var id: String { get }
    static var converters: [any Converter.Type] { get }
}
