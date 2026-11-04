import SwiftUI

/// Morph's app target.
///
/// The main window and the Picker panel are AppKit windows owned by
/// `AppDelegate`, so a background launch for a Finder handoff opens nothing.
/// SwiftUI provides the Settings scene and the standard menus.
@main
struct MorphApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}
