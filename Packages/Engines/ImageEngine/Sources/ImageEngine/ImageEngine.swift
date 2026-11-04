import ConversionKit

/// Raster and vector image conversion.
///
/// Backends: ImageIO first; libwebp, libavif and resvg fill the gaps ImageIO leaves (SPEC §5).
///
/// M1 brings the ImageIO converter; M5 adds the bundled encoders. Adding a converter means writing
/// the type, listing it in `converters`, and giving it a fixture test (SPEC §14).
public enum ImageEngine: EngineModule {
    public static let id = "image"

    public static let converters: [any Converter.Type] = [ImageIOConverter.self]
}
