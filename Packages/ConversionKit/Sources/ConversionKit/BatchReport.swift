import Foundation

/// How a batch went, in the words the finish notification uses (SPEC §4).
public struct BatchReport: Hashable, Sendable {
    public var outputs: [URL] = []
    public var failures: [ConversionError] = []
    public var cancelled = 0

    public init() {}

    public mutating func record(_ event: JobEvent) {
        switch event {
        case .finished(_, let output): outputs.append(output)
        case .failed(_, let error): failures.append(error)
        case .cancelled: cancelled += 1
        case .queued, .started, .progress: break
        }
    }

    /// The notification's text, or `nil` when there's nothing worth saying:
    /// a batch the user cancelled outright doesn't need a notification.
    public var message: String? {
        let converted = outputs.count
        let failed = failures.count
        switch (converted, failed) {
        case (0, 0):
            return nil
        case (0, 1):
            return failures[0].errorDescription ?? "Couldn't convert the file."
        case (0, _):
            return "Couldn't convert \(failed) files."
        case (1, 0):
            return "Converted \(outputs[0].lastPathComponent)."
        case (_, 0):
            return "Converted \(converted) files."
        default:
            return "Converted \(converted) of \(converted + failed) files. \(failed) failed."
        }
    }
}
