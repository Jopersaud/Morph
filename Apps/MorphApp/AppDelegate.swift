import AppKit
import ConversionKit
import FinderSync

/// App lifecycle and every way work arrives: the main window, `morph://`
/// handoffs from the Finder extension, and the Services menu.
///
/// Morph is an agent app (`LSUIElement`): it has a Dock icon only while its
/// window is open. A handoff from Finder runs in the background, posts a
/// notification, and quits once there's nothing left to do (SPEC §6).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let model = JobsModel()
    private let notifier = Notifier()
    private lazy var mainWindow = MainWindowController(model: model)
    private lazy var picker = PickerPanelController(model: model)
    private var idleCheck: Task<Void, Never>?

    func applicationWillFinishLaunching(_ notification: Notification) {
        notifier.install()
        model.onReadOnly = { [weak self] prompt in self?.askAboutReadOnly(prompt) }
        model.onBatchFinished = { [weak self] report in
            guard let self else { return }
            // The Jobs list already shows the result when the window is up.
            if !mainWindow.isVisible || !NSApp.isActive {
                notifier.post(report)
            }
            scheduleIdleCheck()
        }
        mainWindow.onClose = { [weak self] in self?.windowsDidClose() }
        picker.onClose = { [weak self] in self?.windowsDidClose() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = ServicesProvider(delegate: self)
        publishRoutes()

        // A plain launch from the Dock or Finder opens the window; a launch to
        // handle a handoff stays in the background.
        let isDefaultLaunch =
            notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool ?? true
        if isDefaultLaunch {
            showMainWindow()
        } else {
            scheduleIdleCheck()
        }
        #if DEBUG
            handleUITestHandoff()
        #endif
    }

    #if DEBUG
        /// XCUITest launches the app outside LaunchServices, so opening a
        /// `morph://` URL from a test starts a second copy instead of reaching
        /// this one. Tests pass the URL in `MORPH_UI_TEST_HANDOFF` instead.
        private func handleUITestHandoff() {
            guard
                let string = ProcessInfo.processInfo.environment["MORPH_UI_TEST_HANDOFF"],
                let url = URL(string: string),
                let handoff = try? Handoff(url: url)
            else { return }
            handle(handoff)
        }
    #endif

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            showMainWindow()
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Jobs may still be running; `windowsDidClose` quits once they finish.
        false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let files = urls.filter(\.isFileURL)
        if !files.isEmpty {
            // Dropped on the Dock icon or opened with Morph (SPEC §3, E5).
            showPicker(for: files)
        }
        for url in urls where !url.isFileURL {
            do {
                handle(try Handoff(url: url))
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    // MARK: Handoffs

    func handle(_ handoff: Handoff) {
        switch handoff.action {
        case .convert(let target):
            model.submit(handoff.files, to: target)
        case .pick:
            showPicker(for: handoff.files)
        case .refreshRoutes:
            publishRoutes()
        }
        scheduleIdleCheck()
    }

    func showPicker(for files: [URL]) {
        picker.show(files: files)
    }

    /// Writes the route table the Finder extension reads its menu from. Does
    /// nothing until the extension has run once and has a container.
    private func publishRoutes() {
        guard
            let appex = Bundle.main.builtInPlugInsURL?
                .appendingPathComponent("MorphFinderSync.appex"),
            let extensionID = Bundle(url: appex)?.bundleIdentifier,
            let url = RouteTable.url(
                forExtension: extensionID,
                home: FileManager.default.homeDirectoryForCurrentUser)
        else { return }
        try? RouteTable(registry: model.registry).write(to: url)
    }

    // MARK: Windows

    private func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        mainWindow.show()
        NSApp.bringToFront()
    }

    private func windowsDidClose() {
        if !mainWindow.isVisible {
            NSApp.setActivationPolicy(.accessory)
        }
        scheduleIdleCheck()
    }

    /// Quits a few seconds after the last window closes and the last job
    /// ends. Until the menu bar extra arrives (M6), an agent app with no
    /// window has no way to be seen, so it shouldn't linger.
    private func scheduleIdleCheck() {
        idleCheck?.cancel()
        idleCheck = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self, !Task.isCancelled else { return }
            if !mainWindow.isVisible, !picker.isVisible, !model.hasActiveJobs,
                NSApp.modalWindow == nil
            {
                NSApp.terminate(nil)
            }
        }
    }

    // MARK: Read-only folders

    /// One prompt per batch: *Save to…* picks a folder for all the blocked
    /// files, *Skip* leaves them (SPEC §4).
    private func askAboutReadOnly(_ prompt: JobsModel.ReadOnlyPrompt) {
        NSApp.bringToFront()
        let alert = NSAlert()
        alert.messageText = "This folder is read-only"
        let what =
            prompt.files.count == 1
            ? prompt.files[0].lastPathComponent : "\(prompt.files.count) of these files"
        alert.informativeText =
            "Morph can't save beside \(what). Choose another folder for the converted files, "
            + "or skip them."
        alert.addButton(withTitle: "Save to…")
        alert.addButton(withTitle: "Skip")

        var folder: URL?
        if alert.runModal() == .alertFirstButtonReturn {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.prompt = "Save Here"
            folder = panel.runModal() == .OK ? panel.url : nil
        }
        model.resolve(prompt, saveTo: folder)
        scheduleIdleCheck()
    }
}

extension NSApplication {
    /// Makes Morph the active app, for a window the user just asked for.
    ///
    /// The cooperative `activate()` from macOS 14 is ignored when an agent
    /// app launches, so the window would open behind Finder and the Picker
    /// would get no keyboard focus. Only ever called in answer to the user —
    /// launching Morph, *More Options…*, the Services menu, the read-only
    /// prompt — never for a background conversion.
    func bringToFront(then completion: (@MainActor () -> Void)? = nil) {
        // The switch to a regular app takes effect on the next turn of the
        // run loop.
        Task { @MainActor in
            self.activate(ignoringOtherApps: true)
            completion?()
        }
    }
}

/// `Convert with Morph…` in the Services menu and Finder's Quick Actions
/// (SPEC §3, E2): the way in when the Finder extension is off.
@MainActor
final class ServicesProvider: NSObject {
    private weak var delegate: AppDelegate?

    init(delegate: AppDelegate) {
        self.delegate = delegate
    }

    @objc func convertWithMorph(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        let urls =
            pasteboard.readObjects(
                forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
            ?? []
        guard !urls.isEmpty else {
            error.pointee = "Select some files first." as NSString
            return
        }
        delegate?.showPicker(for: urls)
    }
}
