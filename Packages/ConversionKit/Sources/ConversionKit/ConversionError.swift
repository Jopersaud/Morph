import Foundation

/// Everything that can go wrong with one file.
///
/// One bad file never stops the rest of a batch (SPEC §6): the queue records
/// the error against its job and carries on.
public enum ConversionError: Error, Hashable, Sendable {
    /// No registered converter handles this route.
    case unsupported(ConversionRoute)
    /// The source can't be read: missing, damaged, or not downloaded from
    /// iCloud Drive.
    case unreadable(URL, reason: String)
    /// The route exists but this Mac has no encoder for it.
    case encoderUnavailable(FileFormat)
    /// The destination volume ran out of room.
    case diskFull(URL)
    /// The destination folder isn't writable and the user didn't pick another.
    case destinationNotWritable(URL)
    case cancelled
    /// An engine failed for a reason only it understands.
    case engine(String)
}

extension ConversionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupported(let route):
            "Morph can't convert \(route.source.displayName) to \(route.target.displayName)."
        case .unreadable(let url, let reason):
            "Couldn't read \(url.lastPathComponent): \(reason)"
        case .encoderUnavailable(let format):
            "This Mac has no \(format.displayName) encoder available."
        case .diskFull(let url):
            "The disk holding \(url.lastPathComponent) is full."
        case .destinationNotWritable(let url):
            "Morph can't write to \(url.lastPathComponent)."
        case .cancelled:
            "Cancelled."
        case .engine(let message):
            message
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .unsupported:
            "Pick a different target format."
        case .unreadable:
            "Make sure the file has finished downloading, then try again."
        case .encoderUnavailable:
            "Choose another format, or update macOS."
        case .diskFull:
            "Free up some space and try again."
        case .destinationNotWritable:
            "Choose another folder to save into."
        case .cancelled, .engine:
            nil
        }
    }
}
