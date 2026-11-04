import FinderSync
import SwiftUI

/// First launch, two screens at most (SPEC §9): what Morph does, then
/// turning on the Finder extension, with its status updating live.
struct OnboardingView: View {
    static let completedKey = "onboardingCompleted"

    let done: () -> Void

    @State private var page = 0
    @State private var extensionEnabled = FIFinderSyncController.isExtensionEnabled

    var body: some View {
        VStack(spacing: 18) {
            if page == 0 {
                welcome
            } else {
                finderExtension
            }
        }
        .padding(28)
        .frame(width: 440, height: 320)
    }

    private var welcome: some View {
        VStack(spacing: 14) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Convert files right where they are")
                .font(.title2.weight(.semibold))
            Text(
                "Right-click a file in Finder and choose Convert to. The new file appears next "
                    + "to the original."
            )
            .multilineTextAlignment(.center)
            Label("Everything stays on your Mac. No uploads, no accounts.", systemImage: "lock")
                .foregroundStyle(.secondary)
            Spacer()
            Button("Continue") { page = 1 }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("onboarding-continue")
        }
    }

    private var finderExtension: some View {
        VStack(spacing: 14) {
            Text("Turn on the Finder extension")
                .font(.title2.weight(.semibold))
            Text(
                "It adds Convert to to Finder's right-click menu. Turn on Morph under "
                    + "Login Items & Extensions → Finder."
            )
            .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                Image(
                    systemName: extensionEnabled ? "checkmark.circle.fill" : "circle.dashed"
                )
                .foregroundStyle(extensionEnabled ? Color.green : Color.secondary)
                .accessibilityHidden(true)
                Text(extensionEnabled ? "The Finder extension is on." : "Not turned on yet.")
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("extension-status")

            Button("Open Extension Settings") {
                FIFinderSyncController.showExtensionManagementInterface()
            }

            Text("Without it, use Services → Convert with Morph… or drop files on this window.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()
            Button(extensionEnabled ? "Done" : "Skip for Now", action: done)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("onboarding-done")
        }
        .task {
            // Live status: the user flips the switch in System Settings.
            while !Task.isCancelled {
                extensionEnabled = FIFinderSyncController.isExtensionEnabled
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

#Preview {
    OnboardingView {}
}
