import AppKit

// Temporary stand-in until the path bar branch is merged. Same API.
protocol PathBarViewDelegate: AnyObject {
    func pathBar(_ bar: PathBarView, navigateTo folder: URL, select file: URL?)
    func pathBarOpenTerminal(_ bar: PathBarView)
    func pathBarDidEndEditing(_ bar: PathBarView)
}

final class PathBarView: NSView {
    weak var delegate: PathBarViewDelegate?
    var folder = URL(fileURLWithPath: "/") { didSet { field.stringValue = folder.path } }
    var isActive = false
    private(set) var isEditing = false
    private let field = NSTextField(string: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        field.translatesAutoresizingMaskIntoConstraints = false
        field.target = self
        field.action = #selector(go)
        addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: leadingAnchor),
            field.trailingAnchor.constraint(equalTo: trailingAnchor),
            field.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func go() {
        delegate?.pathBar(self, navigateTo: URL(fileURLWithPath: (field.stringValue as NSString).expandingTildeInPath), select: nil)
    }
    func beginEditing() { window?.makeFirstResponder(field) }
    func cancelEditing() { field.stringValue = folder.path }
}
