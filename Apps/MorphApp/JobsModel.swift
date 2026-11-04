import AppKit
import ConversionKit
import Foundation
import Observation

/// Every conversion since launch, from every entry point.
///
/// The model owns the app's one `JobQueue`, mirrors its event stream into
/// rows the Jobs list can draw, and reports each batch when it finishes so the
/// app can post a notification.
@MainActor
@Observable
final class JobsModel {

    struct JobRow: Identifiable {
        enum State {
            case queued
            case running(Double)
            case finished(URL)
            case failed(ConversionError)
            case cancelled

            var isActive: Bool {
                switch self {
                case .queued, .running: true
                case .finished, .failed, .cancelled: false
                }
            }
        }

        let id: UUID
        let request: ConversionRequest
        var state: State
        var sourceName: String { request.source.lastPathComponent }
    }

    /// Files in a folder Morph can't write to, waiting on *Save to…* or
    /// *Skip* (SPEC §4).
    struct ReadOnlyPrompt: Identifiable {
        let id = UUID()
        let files: [URL]
        let target: FileFormat
    }

    /// The drop zone's files, waiting for a target to be picked.
    var dropped: FileSelection
    private(set) var rows: [JobRow] = []

    /// Called when some files can't be saved beside their sources.
    @ObservationIgnored var onReadOnly: ((ReadOnlyPrompt) -> Void)?
    /// Called when every job in a batch has finished, failed or been cancelled.
    @ObservationIgnored var onBatchFinished: ((BatchReport) -> Void)?

    let registry: ConverterRegistry
    private let queue: JobQueue
    private let planner = OutputPlanner()

    private struct Batch {
        var remaining: Set<UUID>
        var report = BatchReport()
    }

    @ObservationIgnored private var pendingRequests: [UUID: ConversionRequest] = [:]
    @ObservationIgnored private var batches: [UUID: Batch] = [:]
    @ObservationIgnored private var batchForJob: [UUID: UUID] = [:]

    init(registry: ConverterRegistry = MorphEngines.makeRegistry()) {
        self.registry = registry
        self.queue = JobQueue(registry: registry)
        self.dropped = FileSelection(registry: registry)
        let events = queue.events()
        Task { [weak self] in
            for await event in events {
                self?.apply(event)
            }
        }
        #if DEBUG
            addFilesFromUITestEnvironment()
        #endif
    }

    // MARK: Converting

    /// Converts the drop zone's files to `target`, then clears the drop zone
    /// for the next batch.
    func convertDropped(to target: FileFormat) {
        submit(dropped.convertible.map(\.url), to: target)
        dropped = FileSelection(registry: registry)
    }

    /// Converts `files` to `target` as one batch. Files in folders Morph can't
    /// write to are held back and offered *Save to…* or *Skip*.
    func submit(_ files: [URL], to target: FileFormat) {
        let blocked = files.filter { !planner.isWritable($0.deletingLastPathComponent()) }
        let writable = files.filter { !blocked.contains($0) }
        enqueue(writable.map { ConversionRequest(source: $0, target: target) })
        if !blocked.isEmpty {
            onReadOnly?(ReadOnlyPrompt(files: blocked, target: target))
        }
    }

    /// Answers the read-only prompt: convert into `folder`, or skip when
    /// `folder` is `nil`. The choice holds for every file in the prompt.
    func resolve(_ prompt: ReadOnlyPrompt, saveTo folder: URL?) {
        guard let folder else { return }
        enqueue(
            prompt.files.map {
                ConversionRequest(source: $0, target: prompt.target, outputFolder: folder)
            })
    }

    private func enqueue(_ requests: [ConversionRequest]) {
        guard !requests.isEmpty else { return }
        let batch = UUID()
        batches[batch] = Batch(remaining: Set(requests.map(\.id)))
        for request in requests {
            pendingRequests[request.id] = request
            batchForJob[request.id] = batch
        }
        Task { await queue.enqueue(requests) }
    }

    func retry(_ row: JobRow) {
        let original = row.request
        enqueue([
            ConversionRequest(
                source: original.source, target: original.target, options: original.options,
                outputFolder: original.outputFolder)
        ])
    }

    func cancel(_ row: JobRow) {
        Task { await queue.cancel(row.id) }
    }

    func cancelAll() {
        Task { await queue.cancelAll() }
    }

    func clearFinished() {
        rows.removeAll { !$0.state.isActive }
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Whether any batch is still waiting on a job.
    var hasActiveJobs: Bool { !batches.isEmpty }
    var hasFinishedJobs: Bool { rows.contains { !$0.state.isActive } }

    /// "12 of 50 done", across the jobs still in the list.
    var progressSummary: String {
        let done = rows.filter { !$0.state.isActive }.count
        return "\(done) of \(rows.count) done"
    }

    // MARK: Events

    private func apply(_ event: JobEvent) {
        if case .queued(let id, _, _) = event {
            guard let request = pendingRequests.removeValue(forKey: id) else { return }
            rows.append(JobRow(id: id, request: request, state: .queued))
            return
        }
        if let index = rows.firstIndex(where: { $0.id == event.jobID }) {
            switch event {
            case .queued: break
            case .started: rows[index].state = .running(0)
            case .progress(_, let fraction): rows[index].state = .running(fraction)
            case .finished(_, let output): rows[index].state = .finished(output)
            case .failed(_, let error): rows[index].state = .failed(error)
            case .cancelled: rows[index].state = .cancelled
            }
        }
        if event.isTerminal {
            finishJob(event)
        }
    }

    private func finishJob(_ event: JobEvent) {
        guard let batchID = batchForJob.removeValue(forKey: event.jobID),
            var batch = batches[batchID]
        else { return }
        batch.report.record(event)
        batch.remaining.remove(event.jobID)
        if batch.remaining.isEmpty {
            batches[batchID] = nil
            onBatchFinished?(batch.report)
        } else {
            batches[batchID] = batch
        }
    }

    #if DEBUG
        /// The UI smoke test can't drag from Finder, so it hands files over in
        /// `MORPH_UI_TEST_FILES`, one path per line.
        private func addFilesFromUITestEnvironment() {
            guard let paths = ProcessInfo.processInfo.environment["MORPH_UI_TEST_FILES"] else {
                return
            }
            dropped.add(paths.split(separator: "\n").map { URL(fileURLWithPath: String($0)) })
        }
    #endif
}
