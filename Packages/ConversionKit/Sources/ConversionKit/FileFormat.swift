import Foundation
import UniformTypeIdentifiers

/// A file format Morph can read or write.
///
/// Formats are values, not cases in an enum, so an engine can add one without
/// touching the core. `FormatCatalog` holds the set that ships with v1.
public struct FileFormat: Hashable, Sendable, Identifiable {
    /// Stable, lowercase identifier used in URLs, settings and the CLI ("png").
    public let id: String
    /// Name shown in menus and chips ("PNG").
    public let displayName: String
    public let utType: UTType
    public let category: Category
    /// Extension used for output files, without the dot ("png").
    public let preferredExtension: String

    public init(
        id: String,
        displayName: String,
        utType: UTType,
        category: Category,
        preferredExtension: String
    ) {
        self.id = id
        self.displayName = displayName
        self.utType = utType
        self.category = category
        self.preferredExtension = preferredExtension
    }

    /// Convenience initializer that resolves the `UTType` at runtime.
    ///
    /// Formats macOS doesn't know about (MKV, AVIF on older systems) fall back
    /// to a dynamic type derived from the extension, so the catalog stays
    /// usable on every supported OS version.
    public init(
        id: String,
        displayName: String,
        typeIdentifier: String? = nil,
        category: Category,
        preferredExtension: String
    ) {
        self.init(
            id: id,
            displayName: displayName,
            utType: Self.resolveType(identifier: typeIdentifier, extension: preferredExtension),
            category: category,
            preferredExtension: preferredExtension
        )
    }

    static func resolveType(identifier: String?, extension ext: String) -> UTType {
        if let identifier, let declared = UTType(identifier) {
            return declared
        }
        if let fromExtension = UTType(filenameExtension: ext) {
            return fromExtension
        }
        // Dynamic (`dyn.…`) type: unknown to the system but still comparable.
        return UTType(tag: ext, tagClass: .filenameExtension, conformingTo: nil) ?? .data
    }

    public enum Category: String, Hashable, Sendable, CaseIterable, Codable {
        case image
        case audio
        case video
        case document
        case archive

        /// Name used for the category headings in the picker panel.
        public var displayName: String {
            switch self {
            case .image: "Images"
            case .audio: "Audio"
            case .video: "Video"
            case .document: "Documents"
            case .archive: "Archives"
            }
        }
    }
}

extension FileFormat: CustomStringConvertible {
    public var description: String { displayName }
}
