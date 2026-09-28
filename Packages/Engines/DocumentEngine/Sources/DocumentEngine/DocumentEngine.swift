import ConversionKit

/// Documents, subtitles and tabular data.
///
/// Backends: PDFKit, NSAttributedString document types, and pure-Swift parsers for SRT/VTT and CSV/TSV/JSON (SPEC §5).
///
/// Empty until **M3**. Adding a converter means writing the type,
/// listing it in `converters`, and giving it a fixture test (SPEC §14).
public enum DocumentEngine: EngineModule {
    public static let id = "document"

    public static let converters: [any Converter.Type] = []
}
