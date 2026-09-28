import ConversionKit
import Testing

@testable import MorphIntents

@Suite("Morph intents")
struct MorphIntentsTests {

    @Test("The intent offers the whole catalog")
    func offeredTargetsMatchCatalog() {
        #expect(MorphIntents.offeredTargets.count == FormatCatalog.all.count)
        #expect(!MorphIntents.offeredTargets.isEmpty)
    }
}
