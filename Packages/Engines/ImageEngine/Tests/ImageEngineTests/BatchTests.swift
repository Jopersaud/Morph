import ConversionKit
import Foundation
import Testing

@testable import ImageEngine

/// The M1 acceptance test: drop 50 HEICs, get 50 JPGs beside them (SPEC §12).
///
/// Runs the real pipeline — `JobQueue`, `FormatDetector`, `OutputPlanner` and
/// the ImageIO converter — exactly as the drop zone does.
@Suite("Batch conversion", .serialized, .timeLimit(.minutes(2)))
struct BatchTests {

    private func makeQueue() -> JobQueue {
        var registry = ConverterRegistry()
        registry.register(engine: ImageEngine.self)
        return JobQueue(registry: registry)
    }

    private func photos(_ count: Int, in folder: TemporaryFolder) throws -> [URL] {
        try (1...count).map {
            try folder.copy(Fixtures.image(FormatCatalog.heic), as: "IMG_\(1000 + $0).HEIC")
        }
    }

    private func run(
        _ sources: [URL], on queue: JobQueue, cancelling: Bool = false
    ) async -> [UUID: JobEvent] {
        let events = queue.events()
        await queue.enqueue(
            sources.map { ConversionRequest(source: $0, target: FormatCatalog.jpeg) })
        if cancelling {
            await queue.cancelAll()
        }
        var results: [UUID: JobEvent] = [:]
        for await event in events where event.isTerminal {
            results[event.jobID] = event
            if results.count == sources.count { break }
        }
        return results
    }

    @Test("50 HEICs in, 50 JPGs out, beside them")
    func fiftyHEICs() async throws {
        let folder = try TemporaryFolder()
        let sources = try photos(50, in: folder)

        let results = await run(sources, on: makeQueue())

        let failures = results.values.filter { if case .finished = $0 { false } else { true } }
        #expect(failures.isEmpty, "\(failures)")
        for source in sources {
            let output = source.deletingPathExtension().appendingPathExtension("jpg")
            let decoded = try DecodedImage(output)
            #expect(decoded.typeIdentifier == "public.jpeg")
            #expect(decoded.width == Fixtures.width && decoded.height == Fixtures.height)
        }
        let names = try folder.names()
        #expect(names.filter { $0.hasSuffix(".jpg") }.count == 50)
        #expect(names.filter { $0.hasSuffix(".HEIC") }.count == 50, "originals are kept")
        #expect(!names.contains { $0.hasSuffix(OutputPlanner.temporarySuffix) })
    }

    @Test("Converting the same batch again numbers the new files")
    func secondRunNumbers() async throws {
        let folder = try TemporaryFolder()
        let sources = try photos(5, in: folder)
        let queue = makeQueue()

        _ = await run(sources, on: queue)
        _ = await run(sources, on: queue)

        let names = try folder.names()
        #expect(names.contains("IMG_1001.jpg"))
        #expect(names.contains("IMG_1001 (1).jpg"))
        #expect(names.filter { $0.hasSuffix(".jpg") }.count == 10)
    }

    @Test("Two sources with the same name both get an output")
    func sameBaseName() async throws {
        let folder = try TemporaryFolder()
        let heic = try folder.copy(Fixtures.image(FormatCatalog.heic), as: "photo.heic")
        let png = try folder.copy(Fixtures.image(FormatCatalog.png), as: "photo.png")

        let results = await run([heic, png], on: makeQueue())

        #expect(results.values.allSatisfy { if case .finished = $0 { true } else { false } })
        let names = try folder.names()
        #expect(names.contains("photo.jpg"))
        #expect(names.contains("photo (1).jpg"))
    }

    @Test("Cancelling a batch leaves no temp or partial files")
    func cancelledBatchIsClean() async throws {
        let folder = try TemporaryFolder()
        let sources = try photos(50, in: folder)

        let results = await run(sources, on: makeQueue(), cancelling: true)

        #expect(results.count == 50)
        let names = try folder.names()
        #expect(!names.contains { $0.hasSuffix(OutputPlanner.temporarySuffix) })
        // Jobs that finished before the cancel are complete JPGs; the rest left nothing.
        let finished = results.values.filter { if case .finished = $0 { true } else { false } }
        #expect(names.filter { $0.hasSuffix(".jpg") }.count == finished.count)
        for name in names where name.hasSuffix(".jpg") {
            _ = try DecodedImage(folder.file(name))
        }
    }
}
