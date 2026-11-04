import AppKit
import ConversionKit
import Foundation
import Observation

/// The main window's state: what's been dropped, and every job since launch.
///
/// The model owns the app's one `JobQueue` and mirrors its event stream into
/// rows the Jobs list can draw.
@MainActor
@Observable
final class JobsModel {

    /// A file waiting in the drop zone for a target to be picked.
    struct SourceFile: Identifiable, Hashable {
        let url: URL
        /// `nil` when Morph doesn't recognise the file.
        let format: FileFormat?
        let size: Int64
        var id: URL { url }
    }

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
        let files: [SourceFile]
        let target: FileFormat
    }

    private(set) var sources: [SourceFile] = []
    private(set) var rows: [JobRow] = []
    var readOnlyPrompt: ReadOnlyPrompt?

    let registry: ConverterRegistry
    private let queue: JobQueue
    private let planner = OutputPlanner()
    private var pendingRequests: [UUID: ConversionRequest] = [:]

    init(registry: ConverterRegistry = MorphEngines.makeRegistry()) {
        self.registry = registry
        self.queue = JobQueue(registry: registry)
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

    // MARK: Sources

    /// Adds dropped or chosen files. A folder contributes the files directly
    /// inside it; duplicates and hidden files are ignored.
    func add(_ urls: [URL]) {
        var known = Set(sources.map(\.url))
        for url in urls.flatMap(Self.expand) where known.insert(url).inserted {
            let format = try? FormatDetector.detect(url)
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            sources.append(SourceFile(url: url, format: format, size: Int64(size)))
        }
    }

    func clearSources() {
        sources = []
    }

    private static func expand(_ url: URL) -> [URL] {
        let url = url.standardizedFileURL
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory
        guard isDirectory == true else { return [url] }
        let contents =
            (try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles])) ?? []
        return
            contents
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory != true }
            .map(\.standardizedFileURL)
            .sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent)
                    == .orderedAscending
            }
    }

    /// Dropped files Morph recognises.
    var convertibleSources: [SourceFile] { sources.filter { $0.format != nil } }

    /// Dropped files Morph can't do anything with; they're left out of the
    /// chips rather than disabling every one of them.
    var skippedSources: [SourceFile] { sources.filter { $0.format == nil } }

    /// Every target at least one dropped file can become.
    var offeredTargets: [FileFormat] {
        let formats = Set(convertibleSources.compactMap(\.format))
        let union = formats.reduce(into: Set<FileFormat>()) {
            $0.formUnion(registry.targets(for: $1))
        }
        return FormatCatalog.all.filter(union.contains)
    }

    /// Whether every dropped file can become `target`.
    func isAvailableForAll(_ target: FileFormat) -> Bool {
        blockers(for: target).isEmpty
    }

    /// The dropped files that can't become `target`, for the chip's tooltip.
    func blockers(for target: FileFormat) -> [SourceFile] {
        convertibleSources.filter { file in
            guard let format = file.format else { return true }
            return !registry.canConvert(from: format, to: target)
        }
    }

    /// "3 images · 12.4 MB"
    var summary: String {
        let files = convertibleSources
        let categories = Set(files.compactMap { $0.format?.category })
        let noun: String
        if categories.count == 1, let category = categories.first {
            noun = Self.noun(for: category, count: files.count)
        } else {
            noun = files.count == 1 ? "file" : "files"
        }
        let bytes = files.reduce(Int64(0)) { $0 + $1.size }
        let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        return "\(files.count) \(noun) · \(size)"
    }

    private static func noun(for category: FileFormat.Category, count: Int) -> String {
        let singular =
            switch category {
            case .image: "image"
            case .audio: "audio file"
            case .video: "video"
            case .document: "document"
            case .archive: "archive"
            }
        return count == 1 ? singular : singular + "s"
    }

    // MARK: Converting

    /// Converts every dropped file to `target`, then clears the drop zone for
    /// the next batch.
    func convert(to target: FileFormat) {
        let files = convertibleSources
        let blocked = files.filter { !planner.isWritable($0.url.deletingLastPathComponent()) }
        let writable = files.filter { !blocked.contains($0) }

        enqueue(writable.map { ConversionRequest(source: $0.url, target: target) })
        if !blocked.isEmpty {
            readOnlyPrompt = ReadOnlyPrompt(files: blocked, target: target)
        }
        clearSources()
    }

    /// Answers the read-only prompt: convert into `folder`, or skip when
    /// `folder` is `nil`. The choice holds for every file in the prompt.
    func resolve(_ prompt: ReadOnlyPrompt, saveTo folder: URL?) {
        if readOnlyPrompt?.id == prompt.id {
            readOnlyPrompt = nil
        }
        guard let folder else { return }
        enqueue(
            prompt.files.map {
                ConversionRequest(source: $0.url, target: prompt.target, outputFolder: folder)
            })
    }

    private func enqueue(_ requests: [ConversionRequest]) {
        guard !requests.isEmpty else { return }
        for request in requests {
            pendingRequests[request.id] = request
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

    var hasActiveJobs: Bool { rows.contains { $0.state.isActive } }
    var hasFinishedJobs: Bool { rows.contains { !$0.state.isActive } }

    /// "12 of 50 done", across the jobs still in the list.
    var progressSummary: String {
        let done = rows.filter { !$0.state.isActive }.count
        return "\(done) of \(rows.count) done"
    }

    /// Overall progress of the jobs in the list, 0...1.
    var overallProgress: Double {
        guard !rows.isEmpty else { return 0 }
        let total = rows.reduce(0.0) { sum, row in
            switch row.state {
            case .queued: sum
            case .running(let fraction): sum + fraction
            case .finished, .failed, .cancelled: sum + 1
            }
        }
        return total / Double(rows.count)
    }

    // MARK: Events

    private func apply(_ event: JobEvent) {
        if case .queued(let id, _, _) = event {
            guard let request = pendingRequests.removeValue(forKey: id) else { return }
            rows.append(JobRow(id: id, request: request, state: .queued))
            return
        }
        guard let index = rows.firstIndex(where: { $0.id == event.jobID }) else { return }
        switch event {
        case .queued: break
        case .started: rows[index].state = .running(0)
        case .progress(_, let fraction): rows[index].state = .running(fraction)
        case .finished(_, let output): rows[index].state = .finished(output)
        case .failed(_, let error): rows[index].state = .failed(error)
        case .cancelled: rows[index].state = .cancelled
        }
    }

    #if DEBUG
        /// The UI smoke test can't drag from Finder, so it hands files over in
        /// `MORPH_UI_TEST_FILES`, one path per line.
        private func addFilesFromUITestEnvironment() {
            guard let paths = ProcessInfo.processInfo.environment["MORPH_UI_TEST_FILES"] else {
                return
            }
            add(paths.split(separator: "\n").map { URL(fileURLWithPath: String($0)) })
        }
    #endif
}
