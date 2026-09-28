import Foundation
import UniformTypeIdentifiers

/// Every format named in the v1 conversion matrix (SPEC §5).
///
/// The catalog says what a format *is*; it says nothing about what Morph can
/// currently convert. Routes come from the converters an engine registers, so a
/// format can sit here before any engine handles it.
public enum FormatCatalog {

    // MARK: Images

    public static let jpeg = FileFormat(
        id: "jpg", displayName: "JPEG", typeIdentifier: "public.jpeg",
        category: .image, preferredExtension: "jpg")
    public static let png = FileFormat(
        id: "png", displayName: "PNG", typeIdentifier: "public.png",
        category: .image, preferredExtension: "png")
    public static let heic = FileFormat(
        id: "heic", displayName: "HEIC", typeIdentifier: "public.heic",
        category: .image, preferredExtension: "heic")
    public static let tiff = FileFormat(
        id: "tiff", displayName: "TIFF", typeIdentifier: "public.tiff",
        category: .image, preferredExtension: "tiff")
    public static let bmp = FileFormat(
        id: "bmp", displayName: "BMP", typeIdentifier: "com.microsoft.bmp",
        category: .image, preferredExtension: "bmp")
    public static let gif = FileFormat(
        id: "gif", displayName: "GIF", typeIdentifier: "com.compuserve.gif",
        category: .image, preferredExtension: "gif")
    public static let webp = FileFormat(
        id: "webp", displayName: "WebP", typeIdentifier: "org.webmproject.webp",
        category: .image, preferredExtension: "webp")
    public static let avif = FileFormat(
        id: "avif", displayName: "AVIF", typeIdentifier: "public.avif",
        category: .image, preferredExtension: "avif")
    public static let svg = FileFormat(
        id: "svg", displayName: "SVG", typeIdentifier: "public.svg-image",
        category: .image, preferredExtension: "svg")

    // MARK: Audio

    public static let wav = FileFormat(
        id: "wav", displayName: "WAV", typeIdentifier: "com.microsoft.waveform-audio",
        category: .audio, preferredExtension: "wav")
    public static let aiff = FileFormat(
        id: "aiff", displayName: "AIFF", typeIdentifier: "public.aiff-audio",
        category: .audio, preferredExtension: "aiff")
    public static let m4a = FileFormat(
        id: "m4a", displayName: "M4A (AAC)", typeIdentifier: "public.mpeg-4-audio",
        category: .audio, preferredExtension: "m4a")
    public static let mp3 = FileFormat(
        id: "mp3", displayName: "MP3", typeIdentifier: "public.mp3",
        category: .audio, preferredExtension: "mp3")
    public static let flac = FileFormat(
        id: "flac", displayName: "FLAC", typeIdentifier: "org.xiph.flac",
        category: .audio, preferredExtension: "flac")
    /// Apple Lossless, carried in an MPEG-4 container, so it shares `.m4a`.
    public static let alac = FileFormat(
        id: "alac", displayName: "ALAC", typeIdentifier: "public.mpeg-4-audio",
        category: .audio, preferredExtension: "m4a")
    public static let ogg = FileFormat(
        id: "ogg", displayName: "OGG", typeIdentifier: "org.xiph.ogg-vorbis",
        category: .audio, preferredExtension: "ogg")
    public static let opus = FileFormat(
        id: "opus", displayName: "Opus", typeIdentifier: nil,
        category: .audio, preferredExtension: "opus")
    public static let wma = FileFormat(
        id: "wma", displayName: "WMA", typeIdentifier: "com.microsoft.windows-media-wma",
        category: .audio, preferredExtension: "wma")

    // MARK: Video

    public static let mov = FileFormat(
        id: "mov", displayName: "MOV", typeIdentifier: "com.apple.quicktime-movie",
        category: .video, preferredExtension: "mov")
    public static let mp4 = FileFormat(
        id: "mp4", displayName: "MP4", typeIdentifier: "public.mpeg-4",
        category: .video, preferredExtension: "mp4")
    public static let m4v = FileFormat(
        id: "m4v", displayName: "M4V", typeIdentifier: "com.apple.m4v-video",
        category: .video, preferredExtension: "m4v")
    public static let mkv = FileFormat(
        id: "mkv", displayName: "MKV", typeIdentifier: "org.matroska.mkv",
        category: .video, preferredExtension: "mkv")
    public static let webm = FileFormat(
        id: "webm", displayName: "WebM", typeIdentifier: "org.webmproject.webm",
        category: .video, preferredExtension: "webm")
    public static let avi = FileFormat(
        id: "avi", displayName: "AVI", typeIdentifier: "public.avi",
        category: .video, preferredExtension: "avi")
    public static let wmv = FileFormat(
        id: "wmv", displayName: "WMV", typeIdentifier: "com.microsoft.windows-media-wmv",
        category: .video, preferredExtension: "wmv")

    // MARK: Documents

    public static let pdf = FileFormat(
        id: "pdf", displayName: "PDF", typeIdentifier: "com.adobe.pdf",
        category: .document, preferredExtension: "pdf")
    public static let docx = FileFormat(
        id: "docx", displayName: "DOCX",
        typeIdentifier: "org.openxmlformats.wordprocessingml.document",
        category: .document, preferredExtension: "docx")
    public static let doc = FileFormat(
        id: "doc", displayName: "DOC", typeIdentifier: "com.microsoft.word.doc",
        category: .document, preferredExtension: "doc")
    public static let rtf = FileFormat(
        id: "rtf", displayName: "RTF", typeIdentifier: "public.rtf",
        category: .document, preferredExtension: "rtf")
    public static let odt = FileFormat(
        id: "odt", displayName: "ODT", typeIdentifier: "org.oasis-open.opendocument.text",
        category: .document, preferredExtension: "odt")
    public static let html = FileFormat(
        id: "html", displayName: "HTML", typeIdentifier: "public.html",
        category: .document, preferredExtension: "html")
    public static let txt = FileFormat(
        id: "txt", displayName: "Plain Text", typeIdentifier: "public.plain-text",
        category: .document, preferredExtension: "txt")
    public static let markdown = FileFormat(
        id: "md", displayName: "Markdown", typeIdentifier: "net.daringfireball.markdown",
        category: .document, preferredExtension: "md")
    public static let srt = FileFormat(
        id: "srt", displayName: "SubRip (SRT)", typeIdentifier: nil,
        category: .document, preferredExtension: "srt")
    public static let vtt = FileFormat(
        id: "vtt", displayName: "WebVTT", typeIdentifier: nil,
        category: .document, preferredExtension: "vtt")
    public static let csv = FileFormat(
        id: "csv", displayName: "CSV", typeIdentifier: "public.comma-separated-values-text",
        category: .document, preferredExtension: "csv")
    public static let tsv = FileFormat(
        id: "tsv", displayName: "TSV", typeIdentifier: "public.tab-separated-values-text",
        category: .document, preferredExtension: "tsv")
    public static let json = FileFormat(
        id: "json", displayName: "JSON", typeIdentifier: "public.json",
        category: .document, preferredExtension: "json")

    // MARK: Archives

    public static let zip = FileFormat(
        id: "zip", displayName: "ZIP", typeIdentifier: "public.zip-archive",
        category: .archive, preferredExtension: "zip")
    public static let tar = FileFormat(
        id: "tar", displayName: "TAR", typeIdentifier: "public.tar-archive",
        category: .archive, preferredExtension: "tar")
    public static let tarGz = FileFormat(
        id: "targz", displayName: "TAR.GZ", typeIdentifier: "org.gnu.gnu-zip-tar-archive",
        category: .archive, preferredExtension: "tar.gz")
    public static let sevenZip = FileFormat(
        id: "7z", displayName: "7-Zip", typeIdentifier: "org.7-zip.7-zip-archive",
        category: .archive, preferredExtension: "7z")
    /// Extract-only: no RAR encoder ships with Morph (SPEC §5).
    public static let rar = FileFormat(
        id: "rar", displayName: "RAR", typeIdentifier: "com.rarlab.rar-archive",
        category: .archive, preferredExtension: "rar")

    /// Every known format, in menu order within each category.
    public static let all: [FileFormat] = [
        jpeg, png, heic, tiff, bmp, gif, webp, avif, svg,
        wav, aiff, m4a, mp3, flac, alac, ogg, opus, wma,
        mov, mp4, m4v, mkv, webm, avi, wmv,
        pdf, docx, doc, rtf, odt, html, txt, markdown, srt, vtt, csv, tsv, json,
        zip, tar, tarGz, sevenZip, rar,
    ]

    private static let byID: [String: FileFormat] =
        Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    /// Looks up a format by its catalog id ("png").
    public static func format(id: String) -> FileFormat? {
        byID[id.lowercased()]
    }

    public static func formats(in category: FileFormat.Category) -> [FileFormat] {
        all.filter { $0.category == category }
    }

    /// Best-effort match from a system type to a catalog format.
    ///
    /// Prefers an exact type match, then conformance, so `public.jpeg` from a
    /// URL's resource values finds JPEG even when the two `UTType`s differ.
    public static func format(matching type: UTType) -> FileFormat? {
        if let exact = all.first(where: { $0.utType == type }) {
            return exact
        }
        return all.first { type.conforms(to: $0.utType) }
    }
}
