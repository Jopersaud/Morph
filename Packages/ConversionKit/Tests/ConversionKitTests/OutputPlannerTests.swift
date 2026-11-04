import Foundation
import Testing

@testable import ConversionKit

@Suite("Output planner")
struct OutputPlannerTests {

    let planner = OutputPlanner()

    @Test("The output goes beside the source with the new extension")
    func besideTheSource() throws {
        let folder = try TemporaryFolder()
        let source = try folder.write("photo.heic")
        let plan = planner.plan(for: source, target: FormatCatalog.jpeg)

        #expect(plan.preferred.lastPathComponent == "photo.jpg")
        #expect(plan.folder.standardizedFileURL == folder.url.standardizedFileURL)
    }

    @Test(
        "Base names survive odd source names",
        arguments: [
            ("photo.heic", "photo"),
            ("my.holiday.photo.heic", "my.holiday.photo"),
            ("README", "README"),
            ("café 🌅 été.heic", "café 🌅 été"),
            ("backup.tar.gz", "backup"),
            ("Backup.TAR.GZ", "Backup"),
            ("photo (1).heic", "photo (1)"),
        ])
    func baseNames(name: String, expected: String) {
        let source = URL(fileURLWithPath: "/tmp").appendingPathComponent(name)
        #expect(OutputPlanner.baseName(of: source) == expected)
    }

    @Test("Multi-part extensions are kept whole")
    func compoundExtension() throws {
        let folder = try TemporaryFolder()
        let source = try folder.write("site")
        let plan = planner.plan(for: source, target: FormatCatalog.tarGz)
        #expect(plan.preferred.lastPathComponent == "site.tar.gz")
        #expect(plan.candidate(2).lastPathComponent == "site (2).tar.gz")
    }

    @Test("The temp file is hidden, unique and in the destination folder")
    func temporaryFile() throws {
        let folder = try TemporaryFolder()
        let source = try folder.write("photo.heic")
        let first = planner.plan(for: source, target: FormatCatalog.jpeg)
        let second = planner.plan(for: source, target: FormatCatalog.jpeg)

        #expect(first.temporary.deletingLastPathComponent() == first.folder)
        #expect(first.temporary.lastPathComponent.hasPrefix(".photo.jpg."))
        #expect(OutputPlanner.isTemporary(first.temporary))
        #expect(first.temporary != second.temporary)
    }

    @Test("Committing renames the temp file into place")
    func commitMovesIntoPlace() throws {
        let folder = try TemporaryFolder()
        let source = try folder.write("photo.heic")
        let plan = planner.plan(for: source, target: FormatCatalog.jpeg)
        try Data("output".utf8).write(to: plan.temporary)

        let output = try planner.commit(plan.temporary, plan: plan)

        #expect(output.lastPathComponent == "photo.jpg")
        #expect(try String(contentsOf: output, encoding: .utf8) == "output")
        #expect(try folder.names() == ["photo.heic", "photo.jpg"])
    }

    @Test("Collisions get numbered names and never overwrite")
    func collisionsAreNumbered() throws {
        let folder = try TemporaryFolder()
        let source = try folder.write("photo.heic")
        try folder.write("photo.jpg", bytes: Array("original".utf8))
        try folder.write("photo (1).jpg", bytes: Array("first copy".utf8))

        let plan = planner.plan(for: source, target: FormatCatalog.jpeg)
        try Data("new".utf8).write(to: plan.temporary)
        let output = try planner.commit(plan.temporary, plan: plan)

        #expect(output.lastPathComponent == "photo (2).jpg")
        let original = folder.url.appendingPathComponent("photo.jpg")
        #expect(try String(contentsOf: original, encoding: .utf8) == "original")
    }

    @Test("Collision checks ignore case, like the file system")
    func collisionsIgnoreCase() throws {
        let folder = try TemporaryFolder()
        let source = try folder.write("photo.heic")
        try folder.write("PHOTO.JPG", bytes: Array("original".utf8))

        let plan = planner.plan(for: source, target: FormatCatalog.jpeg)
        try Data("new".utf8).write(to: plan.temporary)
        let output = try planner.commit(plan.temporary, plan: plan)

        #expect(output.lastPathComponent == "photo (1).jpg")
    }

    @Test("Two outputs wanting the same name at once both survive")
    func concurrentCommits() async throws {
        let folder = try TemporaryFolder()
        let source = try folder.write("photo.heic")
        let planner = planner
        // Twenty jobs, all wanting photo.jpg.
        let plans = (0..<20).map { _ in planner.plan(for: source, target: FormatCatalog.jpeg) }
        for plan in plans {
            try Data("x".utf8).write(to: plan.temporary)
        }

        let outputs = try await withThrowingTaskGroup(of: URL.self) { group in
            for plan in plans {
                group.addTask { try planner.commit(plan.temporary, plan: plan) }
            }
            return try await group.reduce(into: Set<URL>()) { $0.insert($1) }
        }

        #expect(outputs.count == plans.count)
        #expect(outputs.contains { $0.lastPathComponent == "photo.jpg" })
        #expect(outputs.contains { $0.lastPathComponent == "photo (19).jpg" })
    }

    @Test("A read-only folder isn't writable")
    func readOnlyFolder() throws {
        let folder = try TemporaryFolder()
        #expect(planner.isWritable(folder.url))

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o555], ofItemAtPath: folder.url.path)
        #expect(!planner.isWritable(folder.url))
        #expect(!planner.isWritable(folder.url.appendingPathComponent("missing")))
    }

    @Test("Committing into a read-only folder says so")
    func commitIntoReadOnlyFolder() throws {
        let folder = try TemporaryFolder()
        let locked = folder.url.appendingPathComponent("locked", isDirectory: true)
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: false)
        let source = try folder.write("photo.heic")

        // The temp file lives elsewhere so the rename, not the write, fails.
        let plan = planner.plan(for: source, target: FormatCatalog.jpeg, in: locked)
        let written = try folder.write("finished.tmp")
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o555], ofItemAtPath: locked.path)

        #expect(throws: ConversionError.destinationNotWritable(plan.folder)) {
            try planner.commit(written, plan: plan)
        }
    }

    @Test("Stale temp files are cleaned up, and nothing else is")
    func staleTemporaries() throws {
        let folder = try TemporaryFolder()
        try folder.write("photo.heic")
        try folder.write(".photo.jpg.1a2b3c4d.morph-tmp")
        try folder.write(".hidden-but-mine")

        planner.removeStaleTemporaries(in: folder.url)

        #expect(try folder.names() == [".hidden-but-mine", "photo.heic"])
    }
}
