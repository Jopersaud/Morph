import Foundation
import UniformTypeIdentifiers

/// Collects every converter's routes and answers two questions: what can this
/// file become, and who should do the work.
///
/// The Finder extension holds a registry with no engines registered — enough to
/// know the catalog, not enough to convert (SPEC §6).
public struct ConverterRegistry: Sendable {

    private struct Entry: Sendable {
        let type: any Converter.Type
        /// Registration order, used to break ties within a priority.
        let sequence: Int
        let isAvailable: Bool
    }

    private var entries: [Entry] = []

    public init() {}

    // MARK: Registration

    /// Adds a converter. Registering the same `id` twice keeps the first one,
    /// so the app and the CLI can both register the same engines.
    public mutating func register(_ converterType: any Converter.Type) {
        guard !entries.contains(where: { $0.type.id == converterType.id }) else { return }
        entries.append(
            Entry(
                type: converterType,
                sequence: entries.count,
                isAvailable: converterType.isAvailable()
            )
        )
    }

    public mutating func register(engine: any EngineModule.Type) {
        for converterType in engine.converters {
            register(converterType)
        }
    }

    /// Ids of every registered converter, in registration order.
    public var registeredIDs: [String] { entries.map { $0.type.id } }

    // MARK: Lookup

    /// Target formats reachable from `source`, in catalog order.
    ///
    /// Only converters that reported themselves available are considered, so
    /// the UI never offers a route this Mac can't run.
    public func targets(for source: FileFormat) -> [FileFormat] {
        var seen = Set<FileFormat>()
        for entry in entries where entry.isAvailable {
            for target in entry.type.routes[source] ?? [] {
                seen.insert(target)
            }
        }
        return seen.sorted(by: FormatCatalog.menuOrder)
    }

    /// Targets valid for *every* source, which is what the Finder submenu shows
    /// for a multi-file selection (SPEC §3, E1).
    public func commonTargets(for sources: [FileFormat]) -> [FileFormat] {
        guard let first = sources.first else { return [] }
        var shared = Set(targets(for: first))
        for source in sources.dropFirst() {
            shared.formIntersection(targets(for: source))
        }
        return shared.sorted(by: FormatCatalog.menuOrder)
    }

    /// The converter Morph should use for a route: native engines before
    /// bundled libraries, then earliest registered.
    public func converter(from source: FileFormat, to target: FileFormat) -> (any Converter)? {
        converterType(from: source, to: target)?.init()
    }

    public func converterType(
        from source: FileFormat,
        to target: FileFormat
    ) -> (any Converter.Type)? {
        entries
            .filter { $0.isAvailable && ($0.type.routes[source]?.contains(target) ?? false) }
            .min { lhs, rhs in
                if lhs.type.priority != rhs.type.priority {
                    return lhs.type.priority < rhs.type.priority
                }
                return lhs.sequence < rhs.sequence
            }?
            .type
    }

    public func canConvert(from source: FileFormat, to target: FileFormat) -> Bool {
        converterType(from: source, to: target) != nil
    }

    // MARK: Routes

    /// Every route Morph can actually run on this Mac.
    public var availableRoutes: Set<ConversionRoute> {
        routes(includingUnavailable: false)
    }

    /// Every route any registered converter claims, available or not. CI uses
    /// this to check that each advertised route has a fixture test (SPEC §11).
    public var advertisedRoutes: Set<ConversionRoute> {
        routes(includingUnavailable: true)
    }

    private func routes(includingUnavailable: Bool) -> Set<ConversionRoute> {
        var result = Set<ConversionRoute>()
        for entry in entries where includingUnavailable || entry.isAvailable {
            result.formUnion(entry.type.routePairs)
        }
        return result
    }
}

extension FormatCatalog {
    private static let menuIndex: [FileFormat: Int] =
        Dictionary(uniqueKeysWithValues: all.enumerated().map { ($0.element, $0.offset) })

    /// Sorts formats the way the catalog lists them, so every menu, chip grid
    /// and CLI listing agrees. Unknown formats sort last, alphabetically.
    static func menuOrder(_ lhs: FileFormat, _ rhs: FileFormat) -> Bool {
        switch (menuIndex[lhs], menuIndex[rhs]) {
        case (let l?, let r?): l < r
        case (nil, _?): false
        case (_?, nil): true
        case (nil, nil): lhs.id < rhs.id
        }
    }
}
