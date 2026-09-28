import ConversionKit

/// Raster and vector image conversion.
///
/// Backends: ImageIO first; libwebp, libavif and resvg fill the gaps ImageIO leaves (SPEC §5).
///
/// Empty until **M1 (ImageIO) and M5 (bundled encoders)**. Adding a converter means writing the type,
/// listing it in `converters`, and giving it a fixture test (SPEC §14).
public enum ImageEngine: EngineModule {
    public static let id = "image"

    public static let converters: [any Converter.Type] = []
}
