import ConversionKit
import SwiftUI

/// Placeholder for the main window (SPEC §9).
///
/// M1 replaces the body with the real drop zone, target chips and Jobs list.
/// What's here now exists to prove the app links ConversionKit and the engine
/// packages, and to keep the window's size and accessibility shape honest.
struct ContentView: View {
    private let registry = MorphEngines.makeRegistry()

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("Morph")
                .font(.largeTitle.weight(.semibold))

            Text("Everything stays on your Mac.")
                .foregroundStyle(.secondary)

            Divider()
                .padding(.horizontal, 40)

            VStack(spacing: 4) {
                Text("Scaffold build (M0)")
                    .font(.headline)
                Text(status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .accessibilityElement(children: .combine)
        }
        .padding(32)
        .frame(width: 520, height: 420)
    }

    private var status: String {
        let converters = registry.registeredIDs.count
        guard converters > 0 else {
            return """
                \(FormatCatalog.all.count) formats known, no converters registered yet.
                Drop zone and image conversion arrive in M1.
                """
        }
        return "\(converters) converters registered across \(MorphEngines.all.count) engines."
    }
}

#Preview {
    ContentView()
}
