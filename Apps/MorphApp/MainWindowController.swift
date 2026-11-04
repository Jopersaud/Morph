import AppKit
import SwiftUI

/// Owns the main window. AppKit rather than a SwiftUI `Window` scene, so a
/// background launch for a Finder handoff can choose not to open it.
@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate {

    var onClose: (() -> Void)?

    init(model: JobsModel) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: true)
        window.title = "Morph"
        window.contentViewController = NSHostingController(rootView: ContentView(model: model))
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("MainWindow")
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("MainWindowController isn't loaded from a nib")
    }

    var isVisible: Bool { window?.isVisible ?? false }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Let the window finish closing before anyone checks isVisible.
        Task { @MainActor [weak self] in self?.onClose?() }
    }
}
