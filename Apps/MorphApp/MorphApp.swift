import SwiftUI

/// Morph's app target.
///
/// M0 is scaffold: one window, one Settings scene, no conversion. The drop
/// zone and Jobs list arrive in M1, the menu bar extra and Picker panel in M2.
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
