import AppKit
import ConversionKit
import SwiftUI

/// The compact Picker panel (SPEC §3): a floating grid of targets near the
/// cursor, used by Services, `More Options…` and the Dock icon.
@MainActor
final class PickerPanelController: NSObject, NSWindowDelegate {

    var onClose: (() -> Void)?

    private let model: JobsModel
    private var panel: NSPanel?

    init(model: JobsModel) {
        self.model = model
        super.init()
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(files: [URL]) {
        close()
        let selection = FileSelection(registry: model.registry, urls: files)
        let view = PickerView(
            selection: selection,
            convert: { [weak self] target in
                guard let self else { return }
                TargetUsage.record(target)
                model.submit(selection.convertible.map(\.url), to: target)
                close()
            },
            close: { [weak self] in self?.close() })

        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 260),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        panel.title = "Convert with Morph"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        // Steps aside while you're in another app, and is back when you
        // return; Esc or the close button dismisses it.
        panel.hidesOnDeactivate = true
        panel.setAccessibilityIdentifier("picker")
        let host = NSHostingController(rootView: view)
        host.sizingOptions = .preferredContentSize
        panel.contentViewController = host
        panel.delegate = self
        place(panel)

        self.panel = panel
        panel.orderFrontRegardless()
        // Key only once Morph is active, or activation hands key to the main
        // window instead.
        NSApp.bringToFront { [weak panel] in panel?.makeKeyAndOrderFront(nil) }
    }

    func close() {
        guard let panel else { return }
        self.panel = nil
        panel.delegate = nil
        panel.close()
        onClose?()
    }

    /// Just below and centred on the cursor, kept on screen.
    private func place(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let size = panel.frame.size
        var origin = NSPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height - 12)
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
            origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        }
        panel.setFrameOrigin(origin)
    }

    func windowWillClose(_ notification: Notification) {
        panel = nil
        onClose?()
    }

}

/// A titled panel that takes keyboard focus, so typing filters at once.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Remembers which targets get picked, so the most used come first.
enum TargetUsage {
    private static let key = "targetUsage"

    static func count(_ target: FileFormat) -> Int {
        (UserDefaults.standard.dictionary(forKey: key)?[target.id] as? Int) ?? 0
    }

    static func record(_ target: FileFormat) {
        var counts = UserDefaults.standard.dictionary(forKey: key) ?? [:]
        counts[target.id] = ((counts[target.id] as? Int) ?? 0) + 1
        UserDefaults.standard.set(counts, forKey: key)
    }
}

struct PickerView: View {
    let selection: FileSelection
    let convert: (FileFormat) -> Void
    let close: () -> Void

    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var searchFocused: Bool

    private static let columns = 4

    /// Targets every file can become: grouped by category, most used first
    /// within each, then filtered by the query.
    private var targets: [FileFormat] {
        let ordered = FileFormat.Category.allCases.flatMap { category in
            selection.commonTargets
                .filter { $0.category == category }
                .enumerated()
                .sorted { lhs, rhs in
                    let (l, r) = (TargetUsage.count(lhs.element), TargetUsage.count(rhs.element))
                    return l != r ? l > r : lhs.offset < rhs.offset
                }
                .map(\.element)
        }
        return TargetSearch.filter(ordered, query: query)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(selection.summary)
                    .font(.headline)
                    .accessibilityIdentifier("picker-summary")
                if let note = selection.skippedNote {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            TextField("Convert to…", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .accessibilityIdentifier("picker-search")
                .onSubmit(convertHighlighted)
                .onChange(of: query) { highlighted = 0 }
                .onKeyPress(.leftArrow) { move(-1) }
                .onKeyPress(.rightArrow) { move(1) }
                .onKeyPress(.upArrow) { move(-Self.columns) }
                .onKeyPress(.downArrow) { move(Self.columns) }
                .onKeyPress(.escape) {
                    close()
                    return .handled
                }

            if targets.isEmpty {
                Text(
                    selection.commonTargets.isEmpty
                        ? "Morph can't convert these files to a common format."
                        : "No format matches \u{201C}\(query)\u{201D}."
                )
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                grid
            }
        }
        .padding(16)
        .padding(.top, 8)
        .frame(width: 380)
        .onAppear { searchFocused = true }
        // The panel becomes key only after Morph activates, which is after
        // the view appears, so focus is asked for again then.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) {
            _ in searchFocused = true
        }
        .onExitCommand(perform: close)
    }

    private var grid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: Self.columns),
            spacing: 8
        ) {
            ForEach(Array(targets.enumerated()), id: \.element) { index, target in
                Button {
                    convert(target)
                } label: {
                    Text(target.displayName)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            index == highlighted
                                ? Color.accentColor : Color.secondary.opacity(0.12))
                )
                .foregroundStyle(index == highlighted ? Color.white : Color.primary)
                .accessibilityIdentifier("picker-\(target.id)")
                .accessibilityAddTraits(index == highlighted ? .isSelected : [])
            }
        }
    }

    private func move(_ step: Int) -> KeyPress.Result {
        guard !targets.isEmpty else { return .ignored }
        highlighted = min(max(highlighted + step, 0), targets.count - 1)
        return .handled
    }

    private func convertHighlighted() {
        guard targets.indices.contains(highlighted) else { return }
        convert(targets[highlighted])
    }
}
