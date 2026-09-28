import ArchiveEngine
import ConversionKit
import DocumentEngine
import ImageEngine
import MediaEngine

/// The one place that decides which engines the app links.
///
/// Registration order sets the tie-break within a priority, so engines go in
/// the order SPEC §5 lists them. The Finder Sync extension deliberately does
/// *not* use this type: it links ConversionKit alone and stays thin (SPEC §6).
enum MorphEngines {

    static let all: [any EngineModule.Type] = [
        ImageEngine.self,
        MediaEngine.self,
        DocumentEngine.self,
        ArchiveEngine.self,
    ]

    static func makeRegistry() -> ConverterRegistry {
        var registry = ConverterRegistry()
        for engine in all {
            registry.register(engine: engine)
        }
        return registry
    }
}
