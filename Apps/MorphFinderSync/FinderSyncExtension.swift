import AppKit
import ConversionKit
import FinderSync

/// The `Convert to ▸` submenu in Finder's contextual menu (SPEC §3, E1).
///
/// The extension is sandboxed, so it never converts anything. It links
/// ConversionKit for the format catalog and nothing else — no engine package,
/// ever (SPEC §6, §14). M2 wires the menu items to the app over the
/// `morph://` URL scheme.
final class FinderSyncExtension: FIFinderSync {

    /// A registry with no engines registered: enough to describe formats,
    /// deliberately unable to convert.
    private let registry = ConverterRegistry()

    override init() {
        super.init()
        // Watch every volume so the submenu is available wherever files live.
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    override var toolbarItemName: String { "Morph" }

    override var toolbarItemToolTip: String { "Convert with Morph" }

    override var toolbarItemImage: NSImage {
        NSImage(
            systemSymbolName: "arrow.triangle.2.circlepath",
            accessibilityDescription: "Morph"
        ) ?? NSImage()
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        let menu = NSMenu(title: "")
        guard menuKind == .contextualMenuForItems else { return menu }

        let root = NSMenuItem(title: "Convert to", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Convert to")

        let selection = FIFinderSyncController.default().selectedItemURLs() ?? []
        let targets = registry.commonTargets(for: formats(of: selection))

        if targets.isEmpty {
            // M0: no engines are registered anywhere yet, so there is nothing
            // truthful to offer. M1 gives the app its image converters and M2
            // hands the selection off to it.
            let placeholder = NSMenuItem(
                title: "No conversions available yet", action: nil, keyEquivalent: "")
            placeholder.isEnabled = false
            submenu.addItem(placeholder)
        } else {
            for target in targets {
                submenu.addItem(
                    NSMenuItem(title: target.displayName, action: nil, keyEquivalent: ""))
            }
            submenu.addItem(.separator())
            submenu.addItem(
                NSMenuItem(title: "More Options…", action: nil, keyEquivalent: ""))
        }

        root.submenu = submenu
        menu.addItem(root)
        return menu
    }

    /// Identifies the selection by content type, never by extension alone
    /// (SPEC §6).
    private func formats(of urls: [URL]) -> [FileFormat] {
        urls.compactMap { url in
            guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else {
                return nil
            }
            return FormatCatalog.format(matching: type)
        }
    }
}
