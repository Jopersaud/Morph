import SwiftUI

/// Placeholder for the Settings scene (SPEC §9).
///
/// M6 fills in the General, Output, Formats, Finder and Advanced tabs. The
/// scene exists now so the app has a Settings menu item and the window shape
/// is settled.
struct SettingsView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Settings arrive in M6.")
                .font(.headline)
            Text("General, Output, Formats, Finder and Advanced.")
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(width: 420)
    }
}

#Preview {
    SettingsView()
}
