import Foundation

/// Decides where a converted file goes and gets it there safely (SPEC §4).
///
/// - The output sits beside the source as `name.<newext>`.
/// - A collision becomes `name (1).<newext>`, `name (2).<newext>`, and so on.
///   Nothing is ever overwritten.
/// - The converter writes a hidden temp file in the destination folder, which
///   is renamed into place only once it is complete.
///
/// Collisions are settled when the file is committed, not when it is planned:
/// the rename is exclusive, so two jobs that want `photo.jpg` at the same time
/// (say `photo.png` and `photo.tiff` in one batch) end up with `photo.jpg` and
/// `photo (1).jpg`, never one on top of the other.
public struct OutputPlanner: Sendable {

    /// Suffix that marks Morph's temp files, so they can be recognised later.
    public static let temporarySuffix = ".morph-tmp"

    /// Gives up after this many numbered names rather than looping forever.
    static let maxCollisionIndex = 9_999

    public init() {}

    /// Where one output will go.
    public struct Plan: Sendable, Hashable {
        public let folder: URL
        /// The output name without its extension (`photo`).
        public let baseName: String
        /// The output extension without the dot; may have several parts (`tar.gz`).
        public let pathExtension: String
        /// The hidden file the converter writes into.
        public let temporary: URL

        /// The output location with no collision, `photo.jpg`.
        public var preferred: URL { candidate(0) }

        /// The output location for the `index`th collision: `photo (2).jpg`.
        public func candidate(_ index: Int) -> URL {
            let stem = index == 0 ? baseName : "\(baseName) (\(index))"
            let name = pathExtension.isEmpty ? stem : "\(stem).\(pathExtension)"
            return folder.appendingPathComponent(name, isDirectory: false)
        }
    }

    // MARK: Planning

    /// Plans the output for converting `source` to `target`, in `folder` or
    /// beside the source when no folder is given.
    public func plan(for source: URL, target: FileFormat, in folder: URL? = nil) -> Plan {
        let folder = folder ?? source.deletingLastPathComponent()
        let base = Self.baseName(of: source)
        let ext = target.preferredExtension
        let token = UUID().uuidString.prefix(8).lowercased()
        let temporary = folder.appendingPathComponent(
            ".\(base).\(ext).\(token)\(Self.temporarySuffix)", isDirectory: false)
        return Plan(folder: folder, baseName: base, pathExtension: ext, temporary: temporary)
    }

    /// The source's name without its extension. Treats `.tar.gz` as one
    /// extension, and leaves a name with no extension alone.
    public static func baseName(of source: URL) -> String {
        let name = source.lastPathComponent
        for compound in [".tar.gz", ".tar.bz2", ".tar.xz"]
        where name.lowercased().hasSuffix(compound) && name.count > compound.count {
            return String(name.dropLast(compound.count))
        }
        return source.deletingPathExtension().lastPathComponent
    }

    /// Whether Morph can create files in `folder`.
    public func isWritable(_ folder: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
            && FileManager.default.isWritableFile(atPath: folder.path)
    }

    public static func isTemporary(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        return name.hasPrefix(".") && name.hasSuffix(temporarySuffix)
    }

    // MARK: Committing

    /// Moves a finished temp file to the first free name in the plan and
    /// returns where it ended up.
    public func commit(_ written: URL, plan: Plan) throws -> URL {
        for index in 0...Self.maxCollisionIndex {
            let destination = plan.candidate(index)
            // RENAME_EXCL makes "is the name free?" and "take it" one atomic
            // step, so a concurrent job or another app can't slip in between.
            let result = written.withUnsafeFileSystemRepresentation { from in
                destination.withUnsafeFileSystemRepresentation { to in
                    guard let from, let to else { return Int32(-1) }
                    return renamex_np(from, to, UInt32(RENAME_EXCL))
                }
            }
            if result == 0 {
                return destination
            }
            let code = errno
            guard code == EEXIST else {
                throw Self.error(forErrno: code, folder: plan.folder)
            }
        }
        throw ConversionError.engine(
            "There are already too many files named \(plan.preferred.lastPathComponent).")
    }

    /// Deletes a temp file. Used when a job fails or is cancelled.
    public func discard(_ temporary: URL) {
        try? FileManager.default.removeItem(at: temporary)
    }

    /// Deletes Morph temp files left in `folder` by a run that crashed.
    public func removeStaleTemporaries(in folder: URL) {
        let contents =
            (try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: nil)) ?? []
        for url in contents where Self.isTemporary(url) {
            discard(url)
        }
    }

    static func error(forErrno code: Int32, folder: URL) -> ConversionError {
        switch code {
        case ENOSPC, EDQUOT: .diskFull(folder)
        case EACCES, EPERM, EROFS: .destinationNotWritable(folder)
        default:
            .engine(
                "Couldn't save into \(folder.lastPathComponent): "
                    + String(cString: strerror(code)) + ".")
        }
    }
}
