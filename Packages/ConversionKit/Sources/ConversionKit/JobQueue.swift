import Foundation
import UniformTypeIdentifiers
import os

/// What an entry point asks for: convert this file to that format.
///
/// The source's real format is detected when the job runs, not when it is
/// requested, so a request is cheap to make for 200 files at once.
public struct ConversionRequest: Sendable, Identifiable, Hashable {
    public let id: UUID
    public let source: URL
    public let target: FileFormat
    public let options: ConversionOptions
    /// Folder to write into instead of the source's own, for a source in a
    /// read-only folder (SPEC §4). `nil` writes beside the source.
    public let outputFolder: URL?

    public init(
        id: UUID = UUID(),
        source: URL,
        target: FileFormat,
        options: ConversionOptions? = nil,
        outputFolder: URL? = nil
    ) {
        self.id = id
        self.source = source
        self.target = target
        self.options = options ?? .default(for: target.category)
        self.outputFolder = outputFolder
    }
}

/// Runs conversions, a few at a time, and reports on them (SPEC §6).
///
/// Every entry point — the drop zone, the Finder extension, the CLI — feeds
/// requests in here. Jobs are independent: one that fails or is cancelled
/// never stops the rest of its batch.
public actor JobQueue {

    /// How many jobs may run at once. Video gets its own, smaller lane because
    /// the hardware encoder, not the CPU, is the bottleneck.
    public struct Limits: Sendable, Hashable {
        public var general: Int
        public var video: Int

        public init(general: Int, video: Int) {
            self.general = max(1, general)
            self.video = max(1, video)
        }

        public static var `default`: Limits {
            Limits(general: ProcessInfo.processInfo.activeProcessorCount - 2, video: 2)
        }
    }

    enum Lane: Hashable, CaseIterable {
        case general
        case video
    }

    private let runner: JobRunner
    private let limits: Limits
    private let hub = EventHub()

    private var pending: [Lane: [ConversionRequest]] = [:]
    private var running: [UUID: Task<Void, Never>] = [:]
    private var runningCount: [Lane: Int] = [:]

    public init(
        registry: ConverterRegistry,
        limits: Limits = .default,
        planner: OutputPlanner = OutputPlanner()
    ) {
        self.runner = JobRunner(registry: registry, planner: planner)
        self.limits = limits
    }

    /// A stream of every job's events from now on. Each call gets its own
    /// stream, so the Jobs list and a notification observer can both listen.
    public nonisolated func events() -> AsyncStream<JobEvent> {
        hub.subscribe()
    }

    /// Queues the requests and returns their job ids, in order.
    @discardableResult
    public func enqueue(_ requests: [ConversionRequest]) -> [UUID] {
        for request in requests {
            hub.yield(.queued(jobID: request.id, source: request.source, target: request.target))
            pending[Self.lane(for: request), default: []].append(request)
        }
        pump()
        return requests.map(\.id)
    }

    /// Cancels one job, whether it is waiting or already running.
    public func cancel(_ id: UUID) {
        if let task = running[id] {
            task.cancel()
            return
        }
        for lane in Lane.allCases {
            if let index = pending[lane]?.firstIndex(where: { $0.id == id }) {
                pending[lane]?.remove(at: index)
                hub.yield(.cancelled(jobID: id))
                return
            }
        }
    }

    public func cancelAll() {
        for lane in Lane.allCases {
            for request in pending[lane] ?? [] {
                hub.yield(.cancelled(jobID: request.id))
            }
            pending[lane] = []
        }
        for task in running.values {
            task.cancel()
        }
    }

    /// Whether nothing is waiting or running.
    public var isIdle: Bool {
        running.isEmpty && Lane.allCases.allSatisfy { pending[$0]?.isEmpty ?? true }
    }

    // MARK: Scheduling

    static func lane(for request: ConversionRequest) -> Lane {
        if request.target.category == .video { return .video }
        let sourceType = UTType(filenameExtension: request.source.pathExtension)
        return sourceType?.conforms(to: .movie) == true ? .video : .general
    }

    private func limit(for lane: Lane) -> Int {
        switch lane {
        case .general: limits.general
        case .video: limits.video
        }
    }

    private func pump() {
        for lane in Lane.allCases {
            while runningCount[lane, default: 0] < limit(for: lane),
                let request = pending[lane]?.first
            {
                pending[lane]?.removeFirst()
                runningCount[lane, default: 0] += 1
                start(request, in: lane)
            }
        }
    }

    private func start(_ request: ConversionRequest, in lane: Lane) {
        let runner = runner
        let hub = hub
        // Detached so the conversion itself runs off the actor; only the
        // bookkeeping at the end comes back to it.
        running[request.id] = Task.detached(priority: .userInitiated) { [weak self] in
            hub.yield(.started(jobID: request.id))
            let event: JobEvent
            do {
                let output = try await runner.run(request) { fraction in
                    hub.yield(.progress(jobID: request.id, fraction: fraction))
                }
                event = .finished(jobID: request.id, output: output)
            } catch {
                let failure = ConversionError(wrapping: error)
                event =
                    failure == .cancelled
                    ? .cancelled(jobID: request.id)
                    : .failed(jobID: request.id, error: failure)
            }
            hub.yield(event)
            await self?.jobDidEnd(request.id, in: lane)
        }
    }

    private func jobDidEnd(_ id: UUID, in lane: Lane) {
        running[id] = nil
        runningCount[lane, default: 1] -= 1
        pump()
    }
}

/// Does one job from start to finish: detect, plan, convert, commit.
///
/// Kept apart from the actor so conversions run in parallel; it holds nothing
/// mutable.
struct JobRunner: Sendable {
    let registry: ConverterRegistry
    let planner: OutputPlanner

    func run(
        _ request: ConversionRequest,
        progress: @Sendable (Double) -> Void
    ) async throws -> URL {
        try Task.checkCancellation()

        let format = try FormatDetector.detect(request.source)
        guard let converter = registry.converter(from: format, to: request.target) else {
            throw ConversionError.unsupported(
                ConversionRoute(source: format, target: request.target))
        }

        let folder = request.outputFolder ?? request.source.deletingLastPathComponent()
        guard planner.isWritable(folder) else {
            throw ConversionError.destinationNotWritable(folder)
        }

        let plan = planner.plan(for: request.source, target: request.target, in: folder)
        let job = ConversionJob(
            id: request.id,
            source: request.source,
            target: request.target,
            options: request.options,
            destination: plan.temporary)

        var written = plan.temporary
        do {
            progress(0)
            written = try await converter.convert(job, progress: progress)
            // A converter that can't be interrupted mid-write still must not
            // leave a file behind once the job is cancelled.
            try Task.checkCancellation()
            let output = try planner.commit(written, plan: plan)
            progress(1)
            return output
        } catch {
            planner.discard(written)
            planner.discard(plan.temporary)
            throw ConversionError(wrapping: error, folder: folder)
        }
    }
}

extension ConversionError {
    /// Turns whatever an engine threw into something the Jobs list can show.
    init(wrapping error: any Error, folder: URL? = nil) {
        switch error {
        case let error as ConversionError:
            self = error
        case is CancellationError:
            self = .cancelled
        case let error as CocoaError where error.code == .fileWriteOutOfSpace:
            self = folder.map(ConversionError.diskFull) ?? .engine(error.localizedDescription)
        case let error as POSIXError where error.code == .ENOSPC:
            self = folder.map(ConversionError.diskFull) ?? .engine(error.localizedDescription)
        default:
            self = .engine(error.localizedDescription)
        }
    }
}

/// Fans events out to every subscriber. Yielding is synchronous and
/// thread-safe, so a job's events arrive in the order it produced them.
final class EventHub: Sendable {
    private let subscribers = OSAllocatedUnfairLock(
        initialState: [UUID: AsyncStream<JobEvent>.Continuation]())

    func subscribe() -> AsyncStream<JobEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: JobEvent.self)
        let key = UUID()
        subscribers.withLock { $0[key] = continuation }
        continuation.onTermination = { [weak self] _ in
            self?.subscribers.withLock { $0[key] = nil }
        }
        return stream
    }

    func yield(_ event: JobEvent) {
        let continuations = subscribers.withLock { Array($0.values) }
        for continuation in continuations {
            continuation.yield(event)
        }
    }
}
