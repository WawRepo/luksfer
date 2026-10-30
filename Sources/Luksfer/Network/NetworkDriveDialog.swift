import AppKit
import LuksferCore

/// The Add and Edit dialog of a network drive, and the password question (PRD §6.4). Password
/// fields are secure fields and are never filled in: Luksfer never shows a saved password again.
final class NetworkDriveDialog: NSObject, NSTextFieldDelegate {
    let addressField = NSTextField()
    let nameField = NSTextField()
    let userField = NSTextField()
    let passwordField = NSSecureTextField()
    let rememberBox = NSButton(checkboxWithTitle: "Remember the password in the Keychain", target: nil, action: nil)
    let alert = NSAlert()
    private let editing: NetworkDrive?

    /// The dialog on screen now (the self-test fills it in).
    private(set) static var current: NetworkDriveDialog?

    private init(editing drive: NetworkDrive?) {
        editing = drive
        super.init()
        let hasPassword = drive.map { NetworkDrives.shared.passwords.hasPassword(for: $0.id) } ?? false
        alert.messageText = drive.map { "Edit “\($0.name)”" } ?? "Add Network Drive"
        alert.informativeText = "Luksfer keeps the password in the macOS Keychain and never shows it again."
        alert.addButton(withTitle: drive == nil ? "Add and Connect" : "Save")
        alert.addButton(withTitle: "Cancel")

        addressField.placeholderString = #"smb://server/share or \\server\share"#
        userField.placeholderString = "Empty for guest"
        passwordField.placeholderString = hasPassword ? "Saved in the Keychain. Type to change it." : ""
        rememberBox.state = drive == nil || hasPassword ? .on : .off
        if let drive {
            addressField.stringValue = drive.address
            nameField.stringValue = drive.name
            userField.stringValue = drive.user
        }
        addressField.delegate = self
        for (field, name) in [(addressField, "Address"), (nameField, "Name"), (userField, "User name"), (passwordField, "Password")] {
            field.setAccessibilityLabel(name)
            field.widthAnchor.constraint(equalToConstant: 280).isActive = true
        }
        let grid = NSGridView(views: [
            [Self.label("Address:"), addressField],
            [Self.label("Name:"), nameField],
            [Self.label("User name:"), userField],
            [Self.label("Password:"), passwordField],
            [NSGridCell.emptyContentView, rememberBox],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        grid.frame.size = grid.fittingSize
        alert.accessoryView = grid
        alert.window.initialFirstResponder = drive == nil ? addressField : passwordField
        validate()
    }

    private static func label(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.alignment = .right
        return l
    }

    func controlTextDidChange(_ obj: Notification) { validate() }

    /// The first button works only with an address Luksfer can read; the name and user follow it.
    func validate() {
        let address = SMBAddress.parse(addressField.stringValue)
        alert.buttons.first?.isEnabled = address != nil
        nameField.placeholderString = address?.share ?? "Name in the sidebar"
        userField.placeholderString = address?.user ?? "Empty for guest"
    }

    /// Shows the dialog as a sheet. `done` gets the saved drive, and the typed password when it
    /// is for this one connection only (not remembered).
    static func show(editing drive: NetworkDrive?, on window: NSWindow, done: @escaping (NetworkDrive, String?) -> Void) {
        let dialog = NetworkDriveDialog(editing: drive)
        current = dialog
        dialog.alert.beginSheetModal(for: window) { response in
            current = nil
            let typed = dialog.passwordField.stringValue
            dialog.passwordField.stringValue = ""
            guard response == .alertFirstButtonReturn, let drive = dialog.save(password: typed, on: window) else { return }
            done(drive, dialog.rememberBox.state == .off && !typed.isEmpty ? typed : nil)
        }
    }

    private func save(password typed: String, on window: NSWindow) -> NetworkDrive? {
        guard let address = SMBAddress.parse(addressField.stringValue) else { return nil }
        var drive = editing ?? NetworkDrive(name: "", address: "", user: "")
        drive.address = address.text
        drive.name = Self.trimmed(nameField) ?? address.share
        drive.user = Self.trimmed(userField) ?? address.user ?? ""
        let store = NetworkDrives.shared.passwords
        if rememberBox.state == .off || drive.user.isEmpty {
            store.removePassword(for: drive.id)
        } else if !typed.isEmpty {
            do { try store.setPassword(typed, for: drive.id, label: NetworkDrives.keychainLabel(for: drive)) } catch {
                NSAlert(error: error).beginSheetModal(for: window)
            }
        }
        AppServices.shared.update { s in
            if let i = s.networkDrives.firstIndex(where: { $0.id == drive.id }) { s.networkDrives[i] = drive } else { s.networkDrives.append(drive) }
        }
        return drive
    }

    private static func trimmed(_ field: NSTextField) -> String? {
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// Asks for the password of a drive that has none saved. `done` gets it and whether to remember it.
    static func askPassword(for drive: NetworkDrive, on window: NSWindow, done: @escaping (String, Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = "Connect to “\(drive.name)”"
        alert.informativeText = "Enter the password of “\(drive.user)” on \(drive.smb?.host ?? drive.address)."
        let field = NSSecureTextField()
        field.setAccessibilityLabel("Password")
        field.widthAnchor.constraint(equalToConstant: 260).isActive = true
        let remember = NSButton(checkboxWithTitle: "Remember the password in the Keychain", target: nil, action: nil)
        remember.state = .on
        let stack = NSStackView(views: [field, remember])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.frame.size = stack.fittingSize
        alert.accessoryView = stack
        alert.addButton(withTitle: "Connect")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { response in
            let typed = field.stringValue
            field.stringValue = ""
            guard response == .alertFirstButtonReturn, !typed.isEmpty else { return }
            done(typed, remember.state == .on)
        }
    }
}
