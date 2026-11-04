import Foundation

/// Per-category knobs. The UI shows these in the options popover; the CLI maps
/// flags onto them; Settings supplies the defaults.
public enum ConversionOptions: Hashable, Sendable {
    case image(ImageOptions)
    case audio(AudioOptions)
    case video(VideoOptions)
    case document(DocumentOptions)
    case archive(ArchiveOptions)

    public static func `default`(for category: FileFormat.Category) -> ConversionOptions {
        switch category {
        case .image: .image(ImageOptions())
        case .audio: .audio(AudioOptions())
        case .video: .video(VideoOptions())
        case .document: .document(DocumentOptions())
        case .archive: .archive(ArchiveOptions())
        }
    }

    /// The image options, or the image defaults when these options belong to
    /// another category.
    public var imageOptions: ImageOptions {
        if case .image(let options) = self { options } else { ImageOptions() }
    }

    public var category: FileFormat.Category {
        switch self {
        case .image: .image
        case .audio: .audio
        case .video: .video
        case .document: .document
        case .archive: .archive
        }
    }
}

public struct ImageOptions: Hashable, Sendable {
    /// Encoder quality for lossy formats, 0...1. Ignored by PNG and TIFF.
    public var quality: Double
    /// Scale so neither side exceeds this, in pixels. `nil` keeps the size.
    public var maxLongEdge: Int?
    /// Drop location and camera data (SPEC §4).
    public var stripMetadata: Bool
    /// Fill used when flattening transparency into a format without an alpha
    /// channel, as `#RRGGBB`.
    public var flattenBackground: String

    public init(
        quality: Double = 0.85,
        maxLongEdge: Int? = nil,
        stripMetadata: Bool = false,
        flattenBackground: String = "#FFFFFF"
    ) {
        self.quality = quality
        self.maxLongEdge = maxLongEdge
        self.stripMetadata = stripMetadata
        self.flattenBackground = flattenBackground
    }
}

public struct AudioOptions: Hashable, Sendable {
    public enum ChannelLayout: String, Hashable, Sendable, CaseIterable {
        case sameAsSource
        case mono
        case stereo
    }

    /// Target bitrate for lossy formats. `nil` lets the encoder decide.
    public var bitrateKbps: Int?
    /// Output sample rate in Hz. `nil` keeps the source rate.
    public var sampleRate: Int?
    public var channels: ChannelLayout

    public init(
        bitrateKbps: Int? = 192,
        sampleRate: Int? = nil,
        channels: ChannelLayout = .sameAsSource
    ) {
        self.bitrateKbps = bitrateKbps
        self.sampleRate = sampleRate
        self.channels = channels
    }
}

public struct VideoOptions: Hashable, Sendable {
    public enum Preset: String, Hashable, Sendable, CaseIterable {
        case small
        case balanced
        case highQuality
        case sameAsSource
    }

    public enum Codec: String, Hashable, Sendable, CaseIterable {
        case h264
        case hevc
        case vp9
        case sameAsSource
    }

    public var preset: Preset
    /// Cap on the long edge in pixels. `nil` keeps the source resolution.
    public var maxDimension: Int?
    public var codec: Codec
    public var stripAudio: Bool

    public init(
        preset: Preset = .balanced,
        maxDimension: Int? = nil,
        codec: Codec = .sameAsSource,
        stripAudio: Bool = false
    ) {
        self.preset = preset
        self.maxDimension = maxDimension
        self.codec = codec
        self.stripAudio = stripAudio
    }
}

public struct DocumentOptions: Hashable, Sendable {
    public enum PageSize: String, Hashable, Sendable, CaseIterable {
        case usLetter
        case a4
    }

    /// Page size used when paginating text into a PDF.
    public var pageSize: PageSize
    /// Page margin in points.
    public var margin: Double
    /// Resolution used when rasterizing PDF pages to images.
    public var rasterDPI: Double

    public init(pageSize: PageSize = .usLetter, margin: Double = 54, rasterDPI: Double = 144) {
        self.pageSize = pageSize
        self.margin = margin
        self.rasterDPI = rasterDPI
    }
}

public struct ArchiveOptions: Hashable, Sendable {
    /// 0 stores without compressing, 9 compresses hardest.
    public var compressionLevel: Int

    public init(compressionLevel: Int = 6) {
        self.compressionLevel = compressionLevel
    }
}
