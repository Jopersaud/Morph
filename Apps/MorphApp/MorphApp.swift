import SwiftUI

/// Morph's app target.
///
/// One window — the drop zone and the Jobs list — and a Settings scene. The
/// menu bar extra and Picker panel arrive in M2, real Settings in M6.
@main
struct MorphApp: App {
    var body: some Scene {
        Window("Morph", id: "main") {
            ContentView()
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
        }
    }
}
