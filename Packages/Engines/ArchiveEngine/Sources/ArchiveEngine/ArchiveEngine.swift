import ConversionKit

/// Archive creation and extraction.
///
/// Backends: libarchive. ZIP and TAR.GZ can be written; 7Z and RAR are extract-only (SPEC §5).
///
/// Empty until **M5**. Adding a converter means writing the type,
/// listing it in `converters`, and giving it a fixture test (SPEC §14).
public enum ArchiveEngine: EngineModule {
    public static let id = "archive"

    public static let converters: [any Converter.Type] = []
}
