import Foundation
import Testing
import UniformTypeIdentifiers

@testable import ConversionKit

@Suite("Format catalog")
struct FormatCatalogTests {

    @Test("Catalog ids are unique")
    func idsAreUnique() {
        let ids = FormatCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("Catalog ids and extensions are tidy")
    func idsAndExtensionsAreTidy() {
        for format in FormatCatalog.all {
            #expect(format.id == format.id.lowercased(), "\(format.id) should be lowercase")
            #expect(!format.displayName.isEmpty)
            #expect(!format.preferredExtension.isEmpty)
            #expect(
                !format.preferredExtension.hasPrefix("."),
                "\(format.id) extension should not include the dot")
            #expect(format.preferredExtension == format.preferredExtension.lowercased())
        }
    }

    @Test("Every category is represented", arguments: FileFormat.Category.allCases)
    func everyCategoryHasFormats(category: FileFormat.Category) {
        #expect(!FormatCatalog.formats(in: category).isEmpty)
        #expect(!category.displayName.isEmpty)
    }

    @Test("Formats are found by id")
    func lookupByID() {
        #expect(FormatCatalog.format(id: "png") == FormatCatalog.png)
        #expect(FormatCatalog.format(id: "PNG") == FormatCatalog.png)
        #expect(FormatCatalog.format(id: "not-a-format") == nil)
    }

    @Test("Formats are found by system type")
    func lookupByUTType() {
        #expect(FormatCatalog.format(matching: .png) == FormatCatalog.png)
        #expect(FormatCatalog.format(matching: .pdf) == FormatCatalog.pdf)
        #expect(FormatCatalog.format(matching: .jpeg) == FormatCatalog.jpeg)
    }

    @Test("Type resolution falls back to the extension")
    func typeResolutionFallsBack() {
        // A type identifier that no Mac declares still yields a usable type
        // derived from the extension.
        let resolved = FileFormat.resolveType(
            identifier: "com.example.not.a.real.type", extension: "png")
        #expect(resolved == .png)

        let dynamic = FileFormat.resolveType(identifier: nil, extension: "morph-nonsense")
        #expect(dynamic != .data || dynamic.isDynamic)
    }

    @Test("Menu order follows the catalog")
    func menuOrderFollowsCatalog() {
        let shuffled = [FormatCatalog.zip, FormatCatalog.png, FormatCatalog.mp4]
            .sorted(by: FormatCatalog.menuOrder)
        #expect(shuffled == [FormatCatalog.png, FormatCatalog.mp4, FormatCatalog.zip])
    }
}
