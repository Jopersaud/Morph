import Foundation

/// A request from the Finder extension (or anything else) for the app to do
/// something with some files, carried over the `morph://` URL scheme
/// (SPEC §6).
///
///     morph://convert?target=png&path=/Users/me/photo.heic&path=…
///     morph://pick?path=…
///     morph://refresh-routes
///
/// A selection too long for one URL is written to a list file, one path per
/// line, and the URL carries `list=<path>` instead. No App Groups and no XPC:
/// a free Personal Team can't count on the entitlements those need.
public struct Handoff: Hashable, Sendable {

    public enum Action: Hashable, Sendable {
        /// Convert straight away with the default options.
        case convert(FileFormat)
        /// Show the Picker panel for the files.
        case pick
        /// Republish the route table the Finder extension builds its menu from.
        case refreshRoutes
    }

    public var action: Action
    public var files: [URL]

    public static let scheme = "morph"

    /// Longer URLs spill their paths into a list file.
    public static let inlineLimit = 8_000

    static let listFileSuffix = ".morph-handoff"

    public init(action: Action, files: [URL] = []) {
        self.action = action
        self.files = files
    }

    // MARK: Encoding

    /// The URL for this handoff. When the paths don't fit, they're written to
    /// a list file in `spillFolder` and the URL points at that instead.
    public func url(spillFolder: URL = FileManager.default.temporaryDirectory) throws -> URL {
        let inline = try makeURL(items: files.map { URLQueryItem(name: "path", value: $0.path) })
        guard inline.absoluteString.count > Self.inlineLimit else { return inline }

        let list = spillFolder.appendingPathComponent(
            "\(UUID().uuidString)\(Self.listFileSuffix)", isDirectory: false)
        let contents = files.map(\.path).joined(separator: "\n")
        try Data(contents.utf8).write(to: list, options: .atomic)
        return try makeURL(items: [URLQueryItem(name: "list", value: list.path)])
    }

    private func makeURL(items: [URLQueryItem]) throws -> URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch action {
        case .convert(let target):
            components.host = "convert"
            components.queryItems = [URLQueryItem(name: "target", value: target.id)] + items
        case .pick:
            components.host = "pick"
            components.queryItems = items
        case .refreshRoutes:
            components.host = "refresh-routes"
        }
        guard let url = components.url else { throw HandoffError.malformed }
        return url
    }

    // MARK: Decoding

    /// Reads a `morph://` URL. A list file is read and then deleted, so a
    /// handoff can't be replayed from it.
    public init(url: URL) throws {
        guard
            url.scheme?.lowercased() == Self.scheme,
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { throw HandoffError.malformed }

        let items = components.queryItems ?? []
        func values(_ name: String) -> [String] {
            items.filter { $0.name == name }.compactMap(\.value).filter { !$0.isEmpty }
        }

        switch components.host?.lowercased() {
        case "convert":
            guard let id = values("target").first else { throw HandoffError.malformed }
            guard let target = FormatCatalog.format(id: id) else {
                throw HandoffError.unknownTarget(id)
            }
            action = .convert(target)
        case "pick":
            action = .pick
        case "refresh-routes":
            action = .refreshRoutes
        default:
            throw HandoffError.malformed
        }

        var paths = values("path")
        for list in values("list") {
            paths += try Self.readList(at: URL(fileURLWithPath: list))
        }
        files = paths.map { URL(fileURLWithPath: $0) }
    }

    private static func readList(at url: URL) throws -> [String] {
        // Only Morph's own list files, so a crafted URL can't point the app
        // at some other file and delete it.
        guard url.lastPathComponent.hasSuffix(listFileSuffix) else {
            throw HandoffError.malformed
        }
        defer { try? FileManager.default.removeItem(at: url) }
        guard let data = try? Data(contentsOf: url) else { throw HandoffError.listUnreadable }
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
    }
}

public enum HandoffError: Error, Hashable, Sendable {
    case malformed
    case unknownTarget(String)
    case listUnreadable
}

extension HandoffError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .malformed: "Morph didn't understand the request it was sent."
        case .unknownTarget(let id): "Morph doesn't know the format \u{201C}\(id)\u{201D}."
        case .listUnreadable: "Morph couldn't read the list of files it was sent."
        }
    }
}
