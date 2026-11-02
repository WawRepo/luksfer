import AppKit
import NetFS
import LuksferCore

/// Connects network drives (PRD §6.4). macOS does the connection (NetFS); Luksfer hands it the
/// address, the user name and the password from the Keychain, and never shows macOS's own dialog.
final class NetworkDrives {
    static let shared = NetworkDrives()

    /// `LUKSFER_KEYCHAIN` points self-test runs at a keychain file in their sandbox, so they never
    /// touch the user's keychains.
    let passwords: PasswordStore = {
        if let file = TestSwitches.selfTestOnly("LUKSFER_KEYCHAIN") {
            do { return try KeychainPasswordStore(file: URL(fileURLWithPath: file)) } catch {
                fatalError("Luksfer: could not open the test keychain: \(error.localizedDescription)")
            }
        }
        return KeychainPasswordStore()
    }()

    /// `LUKSFER_MOUNT_DIR` makes self-test runs mount inside their sandbox instead of /Volumes.
    private let mountDir = TestSwitches.selfTestOnly("LUKSFER_MOUNT_DIR").map { URL(fileURLWithPath: $0, isDirectory: true) }
    private var pending: [String: Connection] = [:]

    /// A connection being made. The request ID comes a moment after the start.
    private final class Connection {
        var request: AsyncRequestID?
    }

    var drives: [NetworkDrive] { AppServices.shared.settings.networkDrives }

    func isConnecting(_ drive: NetworkDrive) -> Bool { pending[drive.id] != nil }

    /// The mounted volume of the drive, if it is connected.
    func mount(of drive: NetworkDrive, in mounts: [NetworkMount] = NetworkMount.current()) -> NetworkMount? {
        guard let address = drive.smb else { return nil }
        return mounts.first { $0.isMount(of: address) }
    }

    /// Network volumes that are not one of the saved drives (mounted in Finder, for example).
    func otherMounts(in mounts: [NetworkMount] = NetworkMount.current()) -> [NetworkMount] {
        let addresses = drives.compactMap(\.smb)
        return mounts.filter { m in !addresses.contains { m.isMount(of: $0) } }
    }

    /// The label of the Keychain item, so the user can find it in Keychain Access.
    static func keychainLabel(for drive: NetworkDrive) -> String { "Luksfer: \(drive.address)" }

    /// Connects in the background. `done` runs on the main thread with the folder to open, or an
    /// error; it does not run when the user stops the connection. `password` is a password typed
    /// just now; without it the saved one (if any) is used.
    func connect(_ drive: NetworkDrive, password typed: String? = nil, done: @escaping (Result<URL, Error>) -> Void) {
        guard let address = drive.smb else { done(.failure(NetworkDriveError.badAddress(drive.name))); return }
        if let mount = mount(of: drive) { done(.success(mount.folder(for: address))); return }
        guard pending[drive.id] == nil else { return }
        let connection = Connection()
        pending[drive.id] = connection
        let store = passwords, mountDir = self.mountDir
        // Reading the Keychain can wait for a macOS question, so it runs off the main thread too.
        DispatchQueue.global(qos: .userInitiated).async {
            let password = typed ?? (drive.user.isEmpty ? nil : store.password(for: drive.id))
            let open = NSMutableDictionary(dictionary: [kNAUIOptionKey: kNAUIOptionNoUI])
            if drive.user.isEmpty { open[kNetFSUseGuestKey] = true }
            var request: AsyncRequestID?
            let status = NetFSMountURLAsync(address.shareURL as CFURL, mountDir as CFURL?,
                                            drive.user.isEmpty ? nil : drive.user as CFString,
                                            password as CFString?, open, nil, &request, .main) { status, _, points in
                self.finish(connection, drive, address: address, status: status, mountPoints: (points as NSArray?) as? [String], done: done)
            }
            DispatchQueue.main.async {
                if status != 0 {
                    self.finish(connection, drive, address: address, status: status, mountPoints: nil, done: done)
                } else if self.pending[drive.id] === connection {
                    connection.request = request
                } else if let request {
                    NetFSMountURLCancel(request)   // stopped before the request ID came
                }
            }
        }
    }

    /// Stops the connections that are still being made (the Stop button in the status bar).
    func cancelAll() {
        let stopped = pending.values.compactMap(\.request)
        pending.removeAll()
        stopped.forEach { NetFSMountURLCancel($0) }
    }

    private func finish(_ connection: Connection, _ drive: NetworkDrive, address: SMBAddress, status: Int32,
                        mountPoints: [String]?, done: (Result<URL, Error>) -> Void) {
        guard pending[drive.id] === connection else { return }   // stopped by the user
        pending.removeValue(forKey: drive.id)
        if status == 0, let point = mountPoints?.first {
            let mount = NetworkMount(mountPoint: URL(fileURLWithPath: point, isDirectory: true), source: "", fileSystem: "smbfs")
            done(.success(mount.folder(for: address)))
        } else if status == EEXIST, let mount = mount(of: drive) {
            done(.success(mount.folder(for: address)))
        } else {
            done(.failure(NetworkDriveError.connect(drive.name, code: status)))
        }
    }
}

enum NetworkDriveError: LocalizedError {
    case badAddress(String)
    case connect(String, code: Int32)

    var errorDescription: String? {
        switch self {
        case .badAddress(let name), .connect(let name, _): return "Luksfer could not connect to “\(name)”."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .badAddress: return "The address is not an SMB address. Use smb://server/share or \\\\server\\share."
        case .connect(_, let code):
            switch code {
            case EAUTH, EACCES, EPERM: return "The server did not accept the user name or password."
            case ENOENT, ENETFSNOSHARESAVAIL: return "The server has no share with this name."
            case ETIMEDOUT, ECONNREFUSED, EHOSTUNREACH, EHOSTDOWN, ENETUNREACH:
                return "The server does not answer. Check the address and the network."
            case ENETFSPWDNEEDSCHANGE: return "The server wants a new password for this user."
            case ENETFSACCOUNTRESTRICTED: return "The server does not let this user connect now."
            default:
                let reason = code > 0 ? String(cString: strerror(code)) : "error \(code)"
                return "macOS could not connect (\(reason))."
            }
        }
    }

    /// Wrong user, password or address: the Edit button helps.
    var canEdit: Bool {
        if case .connect(_, let code) = self { return [EAUTH, EACCES, EPERM, ENOENT, ENETFSNOSHARESAVAIL].contains(code) }
        return true
    }
}
