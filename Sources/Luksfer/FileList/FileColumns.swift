import AppKit
import LuksferCore

/// The details-view columns (PRD §6.2). Name, Date modified, Type and Size show by default. Folder
/// shows only with search results: it is not in the header's menu, and it is never saved.
enum FileColumn: String, CaseIterable {
    case name, modified, type, size, created, fileExtension, folder

    var title: String {
        switch self {
        case .name: return "Name"
        case .modified: return "Date modified"
        case .type: return "Type"
        case .size: return "Size"
        case .created: return "Date created"
        case .fileExtension: return "Extension"
        case .folder: return "Folder"
        }
    }

    var defaultWidth: CGFloat {
        switch self {
        case .name: return 300
        case .modified, .created: return 130
        case .type: return 130
        case .size: return 70
        case .fileExtension: return 70
        case .folder: return 220
        }
    }

    var hiddenByDefault: Bool { self == .created || self == .fileExtension || self == .folder }

    var sortKey: SortKey {
        switch self {
        case .name, .folder: return .name   // Folder has no sort of its own
        case .modified: return .modified
        case .type: return .type
        case .size: return .size
        case .created: return .created
        case .fileExtension: return .fileExtension
        }
    }

    var identifier: NSUserInterfaceItemIdentifier { .init(rawValue) }

    init?(sortKey: SortKey) {
        guard let c = FileColumn.allCases.first(where: { $0.sortKey == sortKey }) else { return nil }
        self = c
    }
}

/// The Name cell: icon, name, and a cloud mark for files that are only in the cloud.
final class NameCellView: NSTableCellView {
    let icon = NSImageView()
    let label = NSTextField(labelWithString: "")
    let cloud = NSImageView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.imageScaling = .scaleProportionallyUpOrDown
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingMiddle
        label.cell?.isScrollable = false
        label.allowsExpansionToolTips = true
        cloud.translatesAutoresizingMaskIntoConstraints = false
        cloud.image = .symbol("icloud", "Only in the cloud", size: 11)
        cloud.contentTintColor = .secondaryLabelColor
        cloud.toolTip = "Only in the cloud"
        addSubview(icon)
        addSubview(label)
        addSubview(cloud)
        imageView = icon
        textField = label
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            cloud.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 4),
            cloud.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            cloud.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    required init?(coder: NSCoder) { fatalError() }
}

/// A plain text cell for the other columns.
final class TextCellView: NSTableCellView {
    let label = NSTextField(labelWithString: "")

    init(alignment: NSTextAlignment) {
        super.init(frame: .zero)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail
        label.allowsExpansionToolTips = true
        label.alignment = alignment
        label.textColor = .secondaryLabelColor
        addSubview(label)
        textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}
