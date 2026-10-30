import AppKit
import LuksferCore

/// Network drives: add, edit, remove and connect (PRD §6.4).
extension BrowserWindowController {
    @objc func addNetworkDrive(_ sender: Any?) {
        guard let window else { return }
        NetworkDriveDialog.show(editing: nil, on: window) { [weak self] drive, password in
            self?.connect(drive, password: password)
        }
    }

    func editNetworkDrive(_ drive: NetworkDrive) {
        guard let window else { return }
        NetworkDriveDialog.show(editing: drive, on: window) { _, _ in }
    }

    /// Asks first, because the saved password goes too.
    func removeNetworkDrive(_ drive: NetworkDrive) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "Remove “\(drive.name)” from the sidebar?"
        alert.informativeText = "Luksfer also deletes the saved password from the Keychain. The files on the server stay."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            NetworkDrives.shared.passwords.removePassword(for: drive.id)
            AppServices.shared.update { $0.networkDrives.removeAll { $0.id == drive.id } }
        }
    }

    /// Opens the drive in the active pane, and connects first when it is not connected. Without a
    /// saved password (and not as a guest) it asks for one.
    func connect(_ drive: NetworkDrive, password: String? = nil, remember: Bool = false) {
        guard let window else { return }
        let drives = NetworkDrives.shared
        let pane = activePane
        if let mount = drives.mount(of: drive), let address = drive.smb {
            pane.navigate(to: mount.folder(for: address))
            return
        }
        if password == nil, !drive.user.isEmpty, !drives.passwords.hasPassword(for: drive.id) {
            NetworkDriveDialog.askPassword(for: drive, on: window) { [weak self] typed, remember in
                self?.connect(drive, password: typed, remember: remember)
            }
            return
        }
        // The file actions own the progress bar while they run.
        let showsProgress = !FileActions.shared.isBusy
        if showsProgress { statusBar.showProgress("Connecting to “\(drive.name)”…", fraction: nil) }
        drives.connect(drive, password: password) { [weak self] result in
            guard let self else { return }
            if showsProgress { statusBar.hideProgress() }
            switch result {
            case .success(let folder):
                if remember, let password {
                    try? drives.passwords.setPassword(password, for: drive.id, label: NetworkDrives.keychainLabel(for: drive))
                }
                pane.navigate(to: folder)
                statusBar.showMessage("Connected to “\(drive.name)”")
            case .failure(let error):
                showConnectError(error, for: drive)
            }
        }
    }

    private func showConnectError(_ error: Error, for drive: NetworkDrive) {
        guard let window else { return }
        if ProcessInfo.processInfo.environment["LUKSFER_SELFTEST"] != nil {
            let reason = (error as? LocalizedError)?.recoverySuggestion ?? ""
            FileHandle.standardError.write(Data("selftest: error shown: \(error.localizedDescription) \(reason)\n".utf8))
        }
        let alert = NSAlert()
        alert.messageText = error.localizedDescription
        alert.informativeText = (error as? LocalizedError)?.recoverySuggestion ?? ""
        alert.addButton(withTitle: "OK")
        if (error as? NetworkDriveError)?.canEdit ?? true { alert.addButton(withTitle: "Edit…") }
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertSecondButtonReturn,
                  let current = AppServices.shared.settings.networkDrives.first(where: { $0.id == drive.id }) else { return }
            self?.editNetworkDrive(current)
        }
    }
}
