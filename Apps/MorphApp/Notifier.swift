import AppKit
import ConversionKit
@preconcurrency import UserNotifications

/// The finish notification: "Converted 12 files" (SPEC §4). Clicking it
/// reveals the output in Finder.
@MainActor
final class Notifier: NSObject {

    /// Off switch for the notification. Settings (M6) gets a toggle for it.
    static let enabledKey = "notificationsEnabled"

    private let center = UNUserNotificationCenter.current()
    private nonisolated static let outputsKey = "outputs"

    func install() {
        UserDefaults.standard.register(defaults: [Self.enabledKey: true])
        center.delegate = self
    }

    func post(_ report: BatchReport) {
        guard UserDefaults.standard.bool(forKey: Self.enabledKey), let message = report.message
        else { return }

        let content = UNMutableNotificationContent()
        content.title = "Morph"
        content.body = message
        content.userInfo = [Self.outputsKey: report.outputs.map(\.path)]
        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil)

        let center = center
        Task {
            // Asked the first time there's something to say, not at launch.
            guard (try? await center.requestAuthorization(options: [.alert])) == true else {
                return
            }
            try? await center.add(request)
        }
    }
}

extension Notifier: UNUserNotificationCenterDelegate {

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let paths = response.notification.request.content.userInfo[Self.outputsKey] as? [String]
        let urls = (paths ?? []).map { URL(fileURLWithPath: $0) }
        await MainActor.run {
            let existing = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
            if !existing.isEmpty {
                NSWorkspace.shared.activateFileViewerSelecting(existing)
            }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Only posted when the Jobs list isn't on screen, so always show it.
        [.banner, .list]
    }
}
