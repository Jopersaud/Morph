import ConversionKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Still-image conversion through ImageIO, the system's own codecs.
///
/// Routes come from asking ImageIO what this Mac can read and write, not from
/// a fixed list, so a Mac without a HEIC encoder never offers HEIC.
struct ImageIOConverter: Converter {
    static let id = "image.imageio"

    /// The formats M1 covers. GIF, WebP and AVIF sources join in M5 alongside
    /// the bundled encoders.
    static let formats: [FileFormat] = [
        FormatCatalog.jpeg, FormatCatalog.png, FormatCatalog.heic, FormatCatalog.tiff,
        FormatCatalog.bmp,
    ]

    static let readableTypes = Set((CGImageSourceCopyTypeIdentifiers() as? [String]) ?? [])
    static let writableTypes = Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])

    static let routes: [FileFormat: [FileFormat]] = {
        let sources = formats.filter { readableTypes.contains($0.utType.identifier) }
        let targets = formats.filter { writableTypes.contains($0.utType.identifier) }
        return Dictionary(
            uniqueKeysWithValues: sources.map { source in (source, targets.filter { $0 != source })
            }
        )
    }()

    static func isAvailable() -> Bool { !routes.isEmpty }

    /// Formats with no alpha channel, where transparency has to be flattened
    /// onto a background colour rather than left to the encoder.
    static let opaqueFormats: Set<FileFormat> = [FormatCatalog.jpeg]

    /// Formats whose files can't record an EXIF orientation, so the pixels
    /// have to be rotated upright before they are written.
    static let orientationlessFormats: Set<FileFormat> = [FormatCatalog.bmp]

    func convert(_ job: ConversionJob, progress: @Sendable (Double) -> Void) async throws -> URL {
        let options = job.options.imageOptions
        guard Self.writableTypes.contains(job.target.utType.identifier) else {
            throw ConversionError.encoderUnavailable(job.target)
        }
        guard
            let source = CGImageSourceCreateWithURL(
                job.source as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
            CGImageSourceGetCount(source) > 0,
            CGImageSourceGetStatus(source) == .statusComplete
        else {
            throw ConversionError.unreadable(job.source, reason: "the image is damaged.")
        }
        let sourceProperties =
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]

        try Task.checkCancellation()
        progress(0.1)

        guard
            let destination = CGImageDestinationCreateWithURL(
                job.destination as CFURL, job.target.utType.identifier as CFString, 1, nil)
        else {
            throw ConversionError.engine("Couldn't create the \(job.target.displayName) file.")
        }

        let hasAlpha = sourceProperties[kCGImagePropertyHasAlpha] as? Bool ?? false
        let flatten = hasAlpha && Self.opaqueFormats.contains(job.target)
        let needsPixels =
            options.maxLongEdge != nil || options.stripMetadata || flatten
            || Self.orientationlessFormats.contains(job.target)

        if needsPixels {
            // Decode upright, at the requested size, and write only the
            // metadata we choose to carry over.
            var image = try Self.uprightImage(
                from: source, properties: sourceProperties, maxLongEdge: options.maxLongEdge,
                url: job.source)
            if flatten {
                image = try Self.flatten(image, onto: options.flattenBackground)
            }
            progress(0.5)
            let properties = ImageMetadata.properties(
                from: sourceProperties, strip: options.stripMetadata, quality: options.quality,
                target: job.target)
            CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        } else {
            // Straight re-encode: ImageIO carries every bit of metadata
            // across, including the orientation flag.
            let properties = ImageMetadata.encoderProperties(
                quality: options.quality, target: job.target)
            CGImageDestinationAddImageFromSource(destination, source, 0, properties as CFDictionary)
            progress(0.5)
        }

        try Task.checkCancellation()
        guard CGImageDestinationFinalize(destination) else {
            throw ConversionError.engine("Couldn't write the \(job.target.displayName) file.")
        }
        progress(1)
        return job.destination
    }

    // MARK: Pixels

    static func uprightImage(
        from source: CGImageSource,
        properties: [CFString: Any],
        maxLongEdge: Int?,
        url: URL
    ) throws -> CGImage {
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        let longEdge = max(width, height)
        // Never upscale: a cap bigger than the image keeps the image's size.
        let size = min(maxLongEdge ?? longEdge, longEdge)

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(size, 1),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard
            longEdge > 0,
            let image = CGImageSourceCreateThumbnailAtIndex(
                source, 0, thumbnailOptions as CFDictionary)
        else {
            throw ConversionError.unreadable(url, reason: "the image couldn't be decoded.")
        }
        return image
    }

    static func flatten(_ image: CGImage, onto hex: String) throws -> CGImage {
        let space =
            image.colorSpace?.model == .rgb
            ? image.colorSpace : CGColorSpace(name: CGColorSpace.sRGB)
        guard
            let space,
            let context = CGContext(
                data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else {
            throw ConversionError.engine("Couldn't flatten the image's transparency.")
        }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(Self.color(hex: hex))
        context.fill(rect)
        context.draw(image, in: rect)
        guard let flattened = context.makeImage() else {
            throw ConversionError.engine("Couldn't flatten the image's transparency.")
        }
        return flattened
    }

    /// Parses `#RRGGBB`; anything else is white.
    static func color(hex: String) -> CGColor {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
            return CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        }
        return CGColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1)
    }
}

/// Which metadata travels to the output (SPEC §4).
enum ImageMetadata {

    /// Encoder settings that apply whatever happens to the metadata.
    static func encoderProperties(quality: Double, target: FileFormat) -> [CFString: Any] {
        guard lossyFormats.contains(target) else { return [:] }
        return [kCGImageDestinationLossyCompressionQuality: min(max(quality, 0), 1)]
    }

    static let lossyFormats: Set<FileFormat> = [FormatCatalog.jpeg, FormatCatalog.heic]

    /// Metadata for an image whose pixels were decoded upright, so the
    /// orientation flag is reset and stale pixel dimensions are dropped.
    ///
    /// Stripping removes location and camera data — GPS, maker notes, the
    /// camera and lens — but keeps the dates the photo was taken.
    static func properties(
        from source: [CFString: Any],
        strip: Bool,
        quality: Double,
        target: FileFormat
    ) -> [CFString: Any] {
        var result = encoderProperties(quality: quality, target: target)
        result[kCGImagePropertyOrientation] = 1

        for key in [kCGImagePropertyDPIWidth, kCGImagePropertyDPIHeight] {
            result[key] = source[key]
        }

        if var exif = source[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            exif[kCGImagePropertyExifPixelXDimension] = nil
            exif[kCGImagePropertyExifPixelYDimension] = nil
            if strip {
                exif = exif.filter { exifKeysKeptWhenStripping.contains($0.key as String) }
            }
            result[kCGImagePropertyExifDictionary] = exif
        }

        if var tiff = source[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = 1
            if strip {
                tiff = tiff.filter { tiffKeysKeptWhenStripping.contains($0.key as String) }
            }
            result[kCGImagePropertyTIFFDictionary] = tiff
        }

        let carriedOnlyWhenKept = [
            kCGImagePropertyGPSDictionary, kCGImagePropertyExifAuxDictionary,
            kCGImagePropertyMakerAppleDictionary, kCGImagePropertyIPTCDictionary,
        ]
        if !strip {
            for key in carriedOnlyWhenKept {
                result[key] = source[key]
            }
        }
        return result
    }

    // Strings rather than `CFString`s, which aren't `Sendable`.
    static let exifKeysKeptWhenStripping = Set(
        [
            kCGImagePropertyExifDateTimeOriginal, kCGImagePropertyExifDateTimeDigitized,
            kCGImagePropertyExifOffsetTime, kCGImagePropertyExifOffsetTimeOriginal,
            kCGImagePropertyExifOffsetTimeDigitized, kCGImagePropertyExifColorSpace,
        ].map { $0 as String })

    static let tiffKeysKeptWhenStripping = Set(
        [
            kCGImagePropertyTIFFOrientation, kCGImagePropertyTIFFDateTime,
            kCGImagePropertyTIFFXResolution, kCGImagePropertyTIFFYResolution,
            kCGImagePropertyTIFFResolutionUnit,
        ].map { $0 as String })
}
