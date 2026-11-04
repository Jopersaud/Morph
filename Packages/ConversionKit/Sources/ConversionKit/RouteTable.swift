import Foundation

/// The routes this Mac can run, as plain data the Finder extension can read.
///
/// The extension links no engines (SPEC §6), so it can't build a registry that
/// knows any routes. Instead the app publishes this table into the extension's
/// sandbox container whenever it launches, and the extension builds its
/// `Convert to ▸` menu from it.
public struct RouteTable: Codable, Hashable, Sendable {
    /// Bumped when the file's shape changes; a mismatched table is ignored.
    public static let currentVersion = 1

    public var version: Int
    /// Source format id → target format ids.
    public var routes: [String: [String]]

    public init(routes: [String: [String]]) {
        self.version = Self.currentVersion
        self.routes = routes
    }

    public init(registry: ConverterRegistry) {
        var routes: [String: [String]] = [:]
        for route in registry.availableRoutes {
            routes[route.source.id, default: []].append(route.target.id)
        }
        self.init(routes: routes.mapValues { $0.sorted() })
    }

    /// Targets reachable from `source`, in catalog order.
    public func targets(for source: FileFormat) -> [FileFormat] {
        (routes[source.id] ?? [])
            .compactMap(FormatCatalog.format(id:))
            .sorted(by: FormatCatalog.menuOrder)
    }

    /// Targets every source can reach, which is what a multi-file selection
    /// is offered (SPEC §3, E1).
    public func commonTargets(for sources: [FileFormat]) -> [FileFormat] {
        guard let first = sources.first else { return [] }
        var shared = Set(targets(for: first))
        for source in sources.dropFirst() {
            shared.formIntersection(targets(for: source))
        }
        return shared.sorted(by: FormatCatalog.menuOrder)
    }

    // MARK: Storage

    static let fileName = "routes.json"

    /// Where the extension finds the table: inside its own container, which
    /// is the only place its sandbox can read.
    public static var localURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Morph", isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    /// Where the app writes the table for the extension with bundle id
    /// `extensionID`. `nil` until the extension has run once and macOS has
    /// made its container.
    public static func url(forExtension extensionID: String, home: URL) -> URL? {
        let data = home.appendingPathComponent(
            "Library/Containers/\(extensionID)/Data", isDirectory: true)
        guard FileManager.default.fileExists(atPath: data.path) else { return nil }
        return data.appendingPathComponent(
            "Library/Application Support/Morph/\(fileName)", isDirectory: false)
    }

    public func write(to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    /// Reads a table, or `nil` if there isn't a usable one.
    public static func load(from url: URL) -> RouteTable? {
        guard
            let data = try? Data(contentsOf: url),
            let table = try? JSONDecoder().decode(RouteTable.self, from: data),
            table.version == currentVersion
        else { return nil }
        return table
    }
}
