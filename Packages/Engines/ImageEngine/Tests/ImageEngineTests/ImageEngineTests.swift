import ConversionKit
import Testing

@testable import ImageEngine

@Suite("ImageEngine")
struct ImageEngineTests {

    @Test("The engine has a stable id")
    func engineIdentity() {
        #expect(ImageEngine.id == "image")
    }

    @Test("Registering the engine registers each of its converters")
    func registrationIsComplete() {
        var registry = ConverterRegistry()
        registry.register(engine: ImageEngine.self)
        #expect(registry.registeredIDs.count == ImageEngine.converters.count)
    }

    /// Guards the invariant every engine has to keep: if a converter claims a
    /// route and says it is available, the registry must be able to hand back
    /// something that runs it.
    @Test("Every available route resolves to a converter")
    func availableRoutesResolve() {
        var registry = ConverterRegistry()
        registry.register(engine: ImageEngine.self)
        for route in registry.availableRoutes {
            #expect(
                registry.converterType(from: route.source, to: route.target) != nil,
                "no converter for \(route)")
        }
    }
}
