import Foundation
import Testing
import os

@testable import ConversionKit

// MARK: - Stubs

/// Tracks how many stub conversions are in flight at once.
private let inFlight = OSAllocatedUnfairLock(initialState: (current: 0, peak: 0))

/// PNG → JPEG that does what the source's name says:
/// `fail-…` throws, `slow-…` writes half a file and then waits to be cancelled,
/// `busy-…` takes a moment, and anything else succeeds at once.
private struct ScriptedConverter: Converter {
    static let id = "test.scripted"
    static let routes: [FileFormat: [FileFormat]] = [FormatCatalog.png: [FormatCatalog.jpeg]]

    func convert(_ job: ConversionJob, progress: @Sendable (Double) -> Void) async throws -> URL {
        inFlight.withLock {
            $0.current += 1
            $0.peak = max($0.peak, $0.current)
        }
        defer { inFlight.withLock { $0.current -= 1 } }

        let name = job.source.lastPathComponent
        if name.hasPrefix("fail-") {
            try Data("partial".utf8).write(to: job.destination)
            throw ConversionError.engine("The scripted converter failed on purpose.")
        }
        if name.hasPrefix("slow-") {
            try Data("partial".utf8).write(to: job.destination)
            while true {
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        if name.hasPrefix("busy-") {
            try await Task.sleep(for: .milliseconds(50))
        }
        progress(0.5)
        try Data("converted \(name)".utf8).write(to: job.destination)
        return job.destination
    }
}

private func makeQueue(limits: JobQueue.Limits = .default) -> JobQueue {
    var registry = ConverterRegistry()
    registry.register(ScriptedConverter.self)
    return JobQueue(registry: registry, limits: limits)
}

/// Reads events until `count` jobs have finished, failed or been cancelled.
private func terminalEvents(
    from stream: AsyncStream<JobEvent>, count: Int
) async -> [UUID: JobEvent] {
    var result: [UUID: JobEvent] = [:]
    for await event in stream where event.isTerminal {
        result[event.jobID] = event
        if result.count == count { break }
    }
    return result
}

private func requests(for urls: [URL]) -> [ConversionRequest] {
    urls.map { ConversionRequest(source: $0, target: FormatCatalog.jpeg) }
}

// MARK: - Tests

@Suite("Job queue", .serialized, .timeLimit(.minutes(1)))
struct JobQueueTests {

    @Test("A batch converts every file beside its source")
    func batchSucceeds() async throws {
        let folder = try TemporaryFolder()
        let sources = try (1...10).map { try folder.write("photo-\($0).png") }
        let queue = makeQueue()
        let events = queue.events()

        await queue.enqueue(requests(for: sources))
        let results = await terminalEvents(from: events, count: sources.count)

        let outputs = results.values.compactMap { event -> URL? in
            if case .finished(_, let output) = event { output } else { nil }
        }
        #expect(outputs.count == 10)
        for index in 1...10 {
            #expect(FileManager.default.fileExists(atPath: folder.url.path + "/photo-\(index).jpg"))
        }
        #expect(try folder.names().allSatisfy { !$0.hasSuffix(OutputPlanner.temporarySuffix) })
    }

    @Test("A job's events arrive in order")
    func eventsAreOrdered() async throws {
        let folder = try TemporaryFolder()
        let source = try folder.write("photo.png")
        let queue = makeQueue()
        let stream = queue.events()

        let id = try #require(await queue.enqueue(requests(for: [source])).first)

        var kinds: [String] = []
        for await event in stream where event.jobID == id {
            switch event {
            case .queued: kinds.append("queued")
            case .started: kinds.append("started")
            case .progress: if kinds.last != "progress" { kinds.append("progress") }
            case .finished: kinds.append("finished")
            case .failed, .cancelled: kinds.append("other")
            }
            if event.isTerminal { break }
        }
        #expect(kinds == ["queued", "started", "progress", "finished"])
    }

    @Test("One bad file doesn't stop the batch")
    func failuresAreIsolated() async throws {
        let folder = try TemporaryFolder()
        let sources = [
            try folder.write("a.png"),
            try folder.write("fail-b.png"),
            try folder.write("c.png"),
            try folder.write("unknown.dat", bytes: [0x00, 0x01, 0x02]),
            try folder.write("d.png"),
        ]
        let queue = makeQueue()
        let events = queue.events()

        let ids = await queue.enqueue(requests(for: sources))
        let results = await terminalEvents(from: events, count: sources.count)

        let finished = results.values.filter {
            if case .finished = $0 { true } else { false }
        }
        #expect(finished.count == 3)
        guard case .failed(_, .engine) = results[ids[1]] else {
            Issue.record(
                "expected the scripted failure, got \(String(describing: results[ids[1]]))")
            return
        }
        guard case .failed(_, .unknownFormat) = results[ids[3]] else {
            Issue.record("expected an unknown format, got \(String(describing: results[ids[3]]))")
            return
        }
        // The failed job's partial output is gone.
        #expect(try folder.names().allSatisfy { !$0.hasSuffix(OutputPlanner.temporarySuffix) })
        #expect(!FileManager.default.fileExists(atPath: folder.url.path + "/fail-b.jpg"))
    }

    @Test("A route nobody handles fails as unsupported")
    func unsupportedRoute() async throws {
        let folder = try TemporaryFolder()
        let gif = try folder.write("anim.gif", bytes: Signatures.gif)
        let queue = makeQueue()
        let events = queue.events()

        await queue.enqueue(requests(for: [gif]))
        let result = await terminalEvents(from: events, count: 1).values.first

        let route = ConversionRoute(source: FormatCatalog.gif, target: FormatCatalog.jpeg)
        guard case .failed(_, .unsupported(route)) = result else {
            Issue.record("expected unsupported, got \(String(describing: result))")
            return
        }
    }

    @Test("A read-only folder fails the job, and an output folder rescues it")
    func readOnlyFolder() async throws {
        let folder = try TemporaryFolder()
        let locked = folder.url.appendingPathComponent("locked", isDirectory: true)
        let elsewhere = folder.url.appendingPathComponent("elsewhere", isDirectory: true)
        for url in [locked, elsewhere] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        }
        let source = locked.appendingPathComponent("photo.png")
        try Data(Signatures.png).write(to: source)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o555], ofItemAtPath: locked.path)

        let queue = makeQueue()
        let events = queue.events()
        let blocked = ConversionRequest(source: source, target: FormatCatalog.jpeg)
        let redirected = ConversionRequest(
            source: source, target: FormatCatalog.jpeg, outputFolder: elsewhere)

        await queue.enqueue([blocked, redirected])
        let results = await terminalEvents(from: events, count: 2)

        guard case .failed(_, .destinationNotWritable) = results[blocked.id] else {
            Issue.record("expected not writable, got \(String(describing: results[blocked.id]))")
            return
        }
        guard case .finished(_, let output) = results[redirected.id] else {
            Issue.record("expected success, got \(String(describing: results[redirected.id]))")
            return
        }
        #expect(output.deletingLastPathComponent().lastPathComponent == "elsewhere")
    }

    @Test("Cancelling a running job leaves no temp or partial file")
    func cancelRunning() async throws {
        let folder = try TemporaryFolder()
        let source = try folder.write("slow-photo.png")
        let queue = makeQueue()
        let stream = queue.events()

        let id = try #require(await queue.enqueue(requests(for: [source])).first)

        var result: JobEvent?
        for await event in stream where event.jobID == id {
            if case .progress = event {
                // Running, and the partial file is on disk; now cancel.
                await queue.cancel(id)
            }
            if event.isTerminal {
                result = event
                break
            }
        }

        guard case .cancelled = result else {
            Issue.record("expected cancelled, got \(String(describing: result))")
            return
        }
        #expect(try folder.names() == ["slow-photo.png"])
        #expect(await queue.isIdle)
    }

    @Test("Cancel all stops running and waiting jobs alike")
    func cancelAll() async throws {
        let folder = try TemporaryFolder()
        let sources = try (1...6).map { try folder.write("slow-\($0).png") }
        let queue = makeQueue(limits: JobQueue.Limits(general: 2, video: 1))
        let events = queue.events()

        await queue.enqueue(requests(for: sources))
        await queue.cancelAll()
        let results = await terminalEvents(from: events, count: sources.count)

        #expect(results.values.allSatisfy { if case .cancelled = $0 { true } else { false } })
        #expect(try folder.names() == sources.map(\.lastPathComponent).sorted())
    }

    @Test("Cancelling one waiting job leaves the others alone")
    func cancelWaiting() async throws {
        let folder = try TemporaryFolder()
        let sources = try (1...3).map { try folder.write("busy-\($0).png") }
        let queue = makeQueue(limits: JobQueue.Limits(general: 1, video: 1))
        let events = queue.events()

        let ids = await queue.enqueue(requests(for: sources))
        await queue.cancel(ids[2])
        let results = await terminalEvents(from: events, count: 3)

        guard case .cancelled = results[ids[2]] else {
            Issue.record("expected cancelled, got \(String(describing: results[ids[2]]))")
            return
        }
        for id in ids.prefix(2) {
            guard case .finished = results[id] else {
                Issue.record("expected finished, got \(String(describing: results[id]))")
                return
            }
        }
    }

    @Test("No more jobs run at once than the limit allows")
    func concurrencyLimit() async throws {
        let folder = try TemporaryFolder()
        let sources = try (1...12).map { try folder.write("busy-\($0).png") }
        let queue = makeQueue(limits: JobQueue.Limits(general: 3, video: 1))
        let events = queue.events()
        inFlight.withLock { $0 = (0, 0) }

        await queue.enqueue(requests(for: sources))
        _ = await terminalEvents(from: events, count: sources.count)

        let peak = inFlight.withLock { $0.peak }
        #expect(peak <= 3)
        #expect(peak > 1, "jobs should overlap")
    }

    @Test("Videos go in their own lane")
    func lanes() {
        let movie = ConversionRequest(
            source: URL(fileURLWithPath: "/tmp/clip.mov"), target: FormatCatalog.m4a)
        let toVideo = ConversionRequest(
            source: URL(fileURLWithPath: "/tmp/clip.mkv"), target: FormatCatalog.mp4)
        let image = ConversionRequest(
            source: URL(fileURLWithPath: "/tmp/photo.heic"), target: FormatCatalog.jpeg)

        #expect(JobQueue.lane(for: movie) == .video)
        #expect(JobQueue.lane(for: toVideo) == .video)
        #expect(JobQueue.lane(for: image) == .general)
    }

    @Test("Requests default to the target category's options")
    func requestDefaults() {
        let request = ConversionRequest(
            source: URL(fileURLWithPath: "/tmp/photo.heic"), target: FormatCatalog.jpeg)
        #expect(request.options == .image(ImageOptions()))
        #expect(request.outputFolder == nil)
    }
}
