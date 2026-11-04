import Foundation

/// One file, one target format, one resolved destination.
///
/// A job is fully planned before it runs, so a converter never has to decide
/// where its output goes. `JobQueue` hands converters a job whose destination
/// is a hidden temp file beside the final location; once the converter
/// returns, `OutputPlanner` renames it into place and settles name collisions.
public struct ConversionJob: Sendable, Identifiable {
    public let id: UUID
    public let source: URL
    public let target: FileFormat
    public let options: ConversionOptions
    /// Where the converter writes. Always in the folder the output will end up
    /// in — beside the source unless that folder is read-only (SPEC §4).
    public let destination: URL

    public init(
        id: UUID = UUID(),
        source: URL,
        target: FileFormat,
        options: ConversionOptions,
        destination: URL
    ) {
        self.id = id
        self.source = source
        self.target = target
        self.options = options
        self.destination = destination
    }
}

/// What a job did, for the Jobs list and the CLI.
public enum JobEvent: Sendable {
    case queued(jobID: UUID, source: URL, target: FileFormat)
    case started(jobID: UUID)
    case progress(jobID: UUID, fraction: Double)
    case finished(jobID: UUID, output: URL)
    case failed(jobID: UUID, error: ConversionError)
    case cancelled(jobID: UUID)

    public var jobID: UUID {
        switch self {
        case .queued(let id, _, _), .started(let id), .progress(let id, _),
            .finished(let id, _), .failed(let id, _), .cancelled(let id):
            id
        }
    }

    /// Whether this is the last event the job will produce.
    public var isTerminal: Bool {
        switch self {
        case .finished, .failed, .cancelled: true
        case .queued, .started, .progress: false
        }
    }
}
