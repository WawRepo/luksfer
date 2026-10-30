import AppKit
import LuksferCore

/// A small Get Info window: name, type, size, where, dates. A folder's size is counted in the
/// background from file metadata (no file is read).
final class InfoPanel: NSWindowController {
    private static var open: [InfoPanel] = []
    private let sizeLabel = NSTextField(labelWithString: "")
    private var cancelled = false

    static func show(for item: FileItem) {
        let panel = InfoPanel(item: item)
        open.append(panel)
        panel.showWindow(nil)
    }

    private init(item: FileItem) {
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 220), styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        window.title = "\(item.name) Info"
        window.isReleasedWhenClosed = false
        super.init(window: window)

        let icon = NSImageView(image: IconCache.shared.icon(for: item))
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 48).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 48).isActive = true
        let name = NSTextField(wrappingLabelWithString: item.name)
        name.font = .boldSystemFont(ofSize: 14)
        let top = NSStackView(views: [icon, name])
        top.spacing = 12

        sizeLabel.stringValue = item.isFolder ? "Counting…" : "\(Formatters.size(item.size)) (\(item.size.formatted()) bytes)"
        var rows: [(String, NSView)] = [
            ("Type:", NSTextField(labelWithString: FileTypes.displayName(for: item))),
            ("Size:", sizeLabel),
            ("Where:", NSTextField(wrappingLabelWithString: item.url.deletingLastPathComponent().tildePath)),
            ("Created:", NSTextField(labelWithString: Formatters.date.string(from: item.created))),
            ("Modified:", NSTextField(labelWithString: Formatters.date.string(from: item.modified))),
        ]
        if item.isCloudOnly { rows.append(("Stored:", NSTextField(labelWithString: "Only in the cloud"))) }
        let grid = NSGridView(views: rows.map { [NSTextField(labelWithString: $0.0), $0.1] })
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 6
        for r in rows { (r.1 as? NSTextField)?.isSelectable = true }

        let stack = NSStackView(views: [top, grid])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        window.contentView = stack
        window.center()
        NotificationCenter.default.addObserver(self, selector: #selector(closed), name: NSWindow.willCloseNotification, object: window)
        if item.isFolder { countSize(item.url) }
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func closed() {
        cancelled = true
        InfoPanel.open.removeAll { $0 === self }
    }

    private func countSize(_ folder: URL) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var total: Int64 = 0, count = 0
            let e = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey], options: [], errorHandler: { _, _ in true })
            while let url = e?.nextObject() as? URL {
                if self?.cancelled ?? true { return }
                let v = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                if v?.isRegularFile == true { total += Int64(v?.fileSize ?? 0); count += 1 }
            }
            DispatchQueue.main.async {
                self?.sizeLabel.stringValue = "\(Formatters.size(total)) in \(count.formatted()) files"
            }
        }
    }
}
