import ConversionKit
import Foundation

/// Some files the user has picked, and what they can become. Shared by the
/// drop zone and the Picker panel.
struct FileSelection {

    struct File: Identifiable, Hashable {
        let url: URL
        /// `nil` when Morph doesn't recognise the file.
        let format: FileFormat?
        let size: Int64
        var id: URL { url }
    }

    let registry: ConverterRegistry
    private(set) var files: [File] = []

    init(registry: ConverterRegistry, urls: [URL] = []) {
        self.registry = registry
        add(urls)
    }

    var isEmpty: Bool { files.isEmpty }

    /// Adds files. A folder contributes the files directly inside it;
    /// duplicates and hidden files are ignored.
    mutating func add(_ urls: [URL]) {
        var known = Set(files.map(\.url))
        for url in urls.flatMap(Self.expand) where known.insert(url).inserted {
            let format = try? FormatDetector.detect(url)
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            files.append(File(url: url, format: format, size: Int64(size)))
        }
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

    /// Files Morph recognises.
    var convertible: [File] { files.filter { $0.format != nil } }

    /// Files Morph can't do anything with; they're left out of the targets
    /// rather than disabling every one of them.
    var skipped: [File] { files.filter { $0.format == nil } }

    /// Every target at least one file can become.
    var offeredTargets: [FileFormat] {
        let formats = Set(convertible.compactMap(\.format))
        let union = formats.reduce(into: Set<FileFormat>()) {
            $0.formUnion(registry.targets(for: $1))
        }
        return FormatCatalog.all.filter(union.contains)
    }

    /// Targets every recognised file can become.
    var commonTargets: [FileFormat] {
        offeredTargets.filter(isAvailableForAll)
    }

    func isAvailableForAll(_ target: FileFormat) -> Bool {
        blockers(for: target).isEmpty
    }

    /// The files that can't become `target`, for a tooltip.
    func blockers(for target: FileFormat) -> [File] {
        convertible.filter { file in
            guard let format = file.format else { return true }
            return !registry.canConvert(from: format, to: target)
        }
    }

    /// "3 images · 12.4 MB"
    var summary: String {
        let files = convertible
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

    /// "Skipping notes.xyz: not a format Morph converts."
    var skippedNote: String? {
        guard !skipped.isEmpty else { return nil }
        let what = skipped.count == 1 ? skipped[0].url.lastPathComponent : "\(skipped.count) files"
        return "Skipping \(what): not a format Morph converts."
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
}
