import ConversionKit
import Testing

@testable import Morph

/// App-level tests: the wiring between the app target and the packages.
///
/// Per-converter tests live in the packages and run under `swift test`; these
/// run under `xcodebuild test`, where the app target exists.
@Suite("Engine registration")
struct EngineRegistrationTests {

    @Test("The app links every engine named in the spec")
    func allEnginesAreLinked() {
        let ids = MorphEngines.all.map { $0.id }
        #expect(ids == ["image", "media", "document", "archive"])
        #expect(Set(ids).count == ids.count)
    }

    @Test("Building the registry registers every converter exactly once")
    func registryMatchesEngines() {
        let registry = MorphEngines.makeRegistry()
        let expected = MorphEngines.all.reduce(0) { $0 + $1.converters.count }
        #expect(registry.registeredIDs.count == expected)
        #expect(Set(registry.registeredIDs).count == registry.registeredIDs.count)
    }

    @Test("Building the registry twice gives the same result")
    func registryIsDeterministic() {
        #expect(
            MorphEngines.makeRegistry().registeredIDs == MorphEngines.makeRegistry().registeredIDs)
    }

    @Test("Every route the app can offer resolves to a converter")
    func routesResolve() {
        let registry = MorphEngines.makeRegistry()
        for route in registry.availableRoutes {
            #expect(
                registry.converterType(from: route.source, to: route.target) != nil,
                "no converter for \(route)")
        }
    }

    @Test("The format catalog is available to the app")
    func catalogIsReachable() {
        #expect(!FormatCatalog.all.isEmpty)
        #expect(FormatCatalog.format(id: "png") != nil)
    }
}
