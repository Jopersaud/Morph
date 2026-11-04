import Foundation
import Testing

@testable import ConversionKit

@Suite("Handoff and route table")
struct HandoffTests {

    @Test("A convert handoff survives the round trip")
    func convertRoundTrip() throws {
        let files = [
            URL(fileURLWithPath: "/Users/me/Pictures/photo.heic"),
            URL(fileURLWithPath: "/Users/me/Pictures/café & 🌅 #1?.heic"),
        ]
        let handoff = Handoff(action: .convert(FormatCatalog.png), files: files)

        let url = try handoff.url()
        #expect(url.scheme == "morph")
        #expect(url.host == "convert")
        #expect(try Handoff(url: url) == handoff)
    }

    @Test("Pick and refresh handoffs survive the round trip")
    func otherActions() throws {
        let pick = Handoff(action: .pick, files: [URL(fileURLWithPath: "/tmp/a.png")])
        #expect(try Handoff(url: pick.url()) == pick)

        let refresh = Handoff(action: .refreshRoutes)
        #expect(try refresh.url().absoluteString == "morph://refresh-routes")
        #expect(try Handoff(url: refresh.url()) == refresh)
    }

    @Test("A long selection spills into a list file, read once")
    func longSelectionSpills() throws {
        let folder = try TemporaryFolder()
        let files = (1...500).map {
            URL(fileURLWithPath: "/Users/me/Pictures/Holiday 2026/IMG_\($0).HEIC")
        }
        let handoff = Handoff(action: .convert(FormatCatalog.jpeg), files: files)

        let url = try handoff.url(spillFolder: folder.url)

        #expect(url.absoluteString.count < Handoff.inlineLimit)
        #expect(url.absoluteString.contains("list="))
        #expect(try Handoff(url: url) == handoff)
        // The list is deleted once read, so the same URL can't be replayed.
        #expect(try folder.names().isEmpty)
        #expect(throws: HandoffError.listUnreadable) { try Handoff(url: url) }
    }

    @Test("A list parameter must name a Morph list file")
    func listMustBeMorphs() throws {
        let folder = try TemporaryFolder()
        let precious = try folder.write("notes.txt", bytes: Array("keep me".utf8))
        var components = URLComponents(string: "morph://convert?target=png")
        components?.queryItems?.append(URLQueryItem(name: "list", value: precious.path))
        let url = try #require(components?.url)

        #expect(throws: HandoffError.malformed) { try Handoff(url: url) }
        #expect(FileManager.default.fileExists(atPath: precious.path))
    }

    @Test(
        "Malformed URLs are rejected",
        arguments: [
            "https://example.com/convert?target=png",
            "morph://explode?path=/tmp/a.png",
            "morph://convert?path=/tmp/a.png",
        ])
    func malformed(string: String) throws {
        let url = try #require(URL(string: string))
        #expect(throws: HandoffError.malformed) { try Handoff(url: url) }
    }

    @Test("An unknown target is named in the error")
    func unknownTarget() throws {
        let url = try #require(URL(string: "morph://convert?target=xyz&path=/tmp/a.png"))
        #expect(throws: HandoffError.unknownTarget("xyz")) { try Handoff(url: url) }
    }

    @Test("The route table mirrors the registry and round-trips through disk")
    func routeTable() throws {
        var registry = ConverterRegistry()
        registry.register(HeicStub.self)
        registry.register(PngStub.self)
        let table = RouteTable(registry: registry)

        #expect(table.targets(for: FormatCatalog.heic) == [FormatCatalog.jpeg, FormatCatalog.png])
        #expect(
            table.commonTargets(for: [FormatCatalog.heic, FormatCatalog.png])
                == [FormatCatalog.jpeg])
        #expect(table.targets(for: FormatCatalog.mp4).isEmpty)
        #expect(table.commonTargets(for: []).isEmpty)

        let folder = try TemporaryFolder()
        let file = folder.url.appendingPathComponent("nested/routes.json")
        try table.write(to: file)
        #expect(RouteTable.load(from: file) == table)
    }

    @Test("A table from another version is ignored")
    func routeTableVersion() throws {
        let folder = try TemporaryFolder()
        let file = try folder.write(
            "routes.json", bytes: Array(#"{"version": 99, "routes": {"heic": ["jpg"]}}"#.utf8))
        #expect(RouteTable.load(from: file) == nil)
        #expect(RouteTable.load(from: folder.url.appendingPathComponent("missing.json")) == nil)
    }

    @Test("The app only writes into a container that exists")
    func containerLocation() throws {
        let home = try TemporaryFolder()
        #expect(RouteTable.url(forExtension: "com.example.Ext", home: home.url) == nil)

        let data = home.url.appendingPathComponent("Library/Containers/com.example.Ext/Data")
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        let url = try #require(RouteTable.url(forExtension: "com.example.Ext", home: home.url))
        #expect(url.path.hasSuffix("Data/Library/Application Support/Morph/routes.json"))
    }
}

private struct HeicStub: Converter {
    static let id = "test.heic"
    static let routes: [FileFormat: [FileFormat]] = [
        FormatCatalog.heic: [FormatCatalog.png, FormatCatalog.jpeg]
    ]
    func convert(_ job: ConversionJob, progress: @Sendable (Double) -> Void) async throws -> URL {
        job.destination
    }
}

private struct PngStub: Converter {
    static let id = "test.png"
    static let routes: [FileFormat: [FileFormat]] = [FormatCatalog.png: [FormatCatalog.jpeg]]
    func convert(_ job: ConversionJob, progress: @Sendable (Double) -> Void) async throws -> URL {
        job.destination
    }
}
