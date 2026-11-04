import AppKit
import ConversionKit
import FinderSync

/// The `Convert to ▸` submenu in Finder's contextual menu (SPEC §3, E1).
///
/// The extension is sandboxed, so it never converts anything. It links
/// ConversionKit and nothing else — no engine package, ever (SPEC §6, §14).
/// It learns which routes exist from the table the app publishes into its
/// container, and hands each click to the app over `morph://`.
final class FinderSyncExtension: FIFinderSync {

    /// Menu item tags are indexes into the catalog; Finder copies the menu
    /// into its own process, so a tag is the one thing that reliably survives.
    private static let moreOptionsTag = -1
    private static let setUpTag = -2

    override init() {
        super.init()
        // Watch every volume so the submenu is available wherever files live.
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
        // First run: the app hasn't written our route table yet, because our
        // container didn't exist. Ask it to, in the background.
        if Self.loadRoutes() == nil {
            open(Handoff(action: .refreshRoutes))
        }
    }

    override var toolbarItemName: String { "Morph" }

    override var toolbarItemToolTip: String { "Convert with Morph" }

    override var toolbarItemImage: NSImage {
        NSImage(
            systemSymbolName: "arrow.triangle.2.circlepath",
            accessibilityDescription: "Morph"
        ) ?? NSImage()
    }

    // MARK: Menu

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        let menu = NSMenu(title: "")
        guard menuKind == .contextualMenuForItems else { return menu }

        let selection = FIFinderSyncController.default().selectedItemURLs() ?? []
        let formats = Self.formats(of: selection)
        // Say nothing about folders or files Morph doesn't know at all.
        guard !selection.isEmpty, formats.count == selection.count else { return menu }

        let root = NSMenuItem(title: "Convert to", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Convert to")

        guard let routes = Self.loadRoutes() else {
            submenu.addItem(item("Set Up Morph…", tag: Self.setUpTag))
            root.submenu = submenu
            menu.addItem(root)
            return menu
        }

        let targets = routes.commonTargets(for: formats)
        guard !targets.isEmpty else { return menu }

        for target in targets {
            guard let index = FormatCatalog.all.firstIndex(of: target) else { continue }
            submenu.addItem(item(target.displayName, tag: index))
        }
        submenu.addItem(.separator())
        submenu.addItem(item("More Options…", tag: Self.moreOptionsTag))

        root.submenu = submenu
        menu.addItem(root)
        return menu
    }

    private func item(_ title: String, tag: Int) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(choose(_:)), keyEquivalent: "")
        item.target = self
        item.tag = tag
        return item
    }

    @objc private func choose(_ sender: NSMenuItem) {
        let selection = FIFinderSyncController.default().selectedItemURLs() ?? []
        switch sender.tag {
        case Self.setUpTag:
            open(Handoff(action: .refreshRoutes))
        case Self.moreOptionsTag:
            open(Handoff(action: .pick, files: selection))
        case FormatCatalog.all.indices:
            open(Handoff(action: .convert(FormatCatalog.all[sender.tag]), files: selection))
        default:
            break
        }
    }

    private func open(_ handoff: Handoff) {
        guard let url = try? handoff.url() else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: Helpers

    private static func loadRoutes() -> RouteTable? {
        RouteTable.localURL.flatMap(RouteTable.load(from:))
    }

    /// Identifies the selection by its system type. The sandbox can't read
    /// file contents, and the menu has to appear in well under 100 ms
    /// (SPEC §10); the app checks the real content before converting.
    private static func formats(of urls: [URL]) -> [FileFormat] {
        urls.compactMap { url in
            guard
                let values = try? url.resourceValues(forKeys: [.contentTypeKey, .isDirectoryKey]),
                values.isDirectory != true,
                let type = values.contentType
            else { return nil }
            return FormatCatalog.format(matching: type)
        }
    }
}
