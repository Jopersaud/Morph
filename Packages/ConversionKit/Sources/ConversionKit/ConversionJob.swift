import Foundation

/// One file, one target format, one resolved destination.
///
/// A job is fully planned before it runs: `OutputPlanner` (M1) picks the
/// destination and settles name collisions, so a converter never has to decide
/// where its output goes.
public struct ConversionJob: Sendable, Identifiable {
    public let id: UUID
    public let source: URL
    public let target: FileFormat
    public let options: ConversionOptions
    /// Final location for the output, beside the source unless the folder is
    /// read-only (SPEC §4).
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
    case started(jobID: UUID)
    case progress(jobID: UUID, fraction: Double)
    case finished(jobID: UUID, output: URL)
    case failed(jobID: UUID, error: ConversionError)
    case cancelled(jobID: UUID)
}
