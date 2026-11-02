import Foundation
import Security

/// Keeps the passwords of network drives. Luksfer never writes a password anywhere else.
public protocol PasswordStore: AnyObject {
    /// Whether a password is saved. It does not read the password, so macOS never asks about it.
    func hasPassword(for id: String) -> Bool
    /// Reads the password to hand it to macOS for a connection. macOS may ask the user first.
    func password(for id: String) -> String?
    func setPassword(_ password: String, for id: String, label: String) throws
    func removePassword(for id: String)
}

public struct KeychainError: LocalizedError {
    public let status: OSStatus
    public var errorDescription: String? {
        "The Keychain refused the password: " + ((SecCopyErrorMessageString(status, nil) as String?) ?? "error \(status)")
    }
}

/// Saves passwords in the macOS Keychain as generic passwords under Luksfer's own service name,
/// one item per drive. Tests give it a keychain file in their sandbox, so they never touch the
/// user's keychains.
///
/// The login keychain is a file keychain: its items never sync to iCloud, and macOS ignores
/// `kSecAttrAccessible` there. The data protection keychain, which honors it, needs an Apple
/// developer team, so it has to wait for a signed release.
public final class KeychainPasswordStore: PasswordStore {
    public static let service = "io.github.wawrepo.luksfer.network-drive"
    private let keychain: SecKeychain?

    /// The user's login keychain.
    public init() { keychain = nil }

    /// A keychain file of its own, made when it is missing. It is not added to the user's keychain list.
    public init(file: URL) throws {
        let pass = "luksfer-test"   // a sandbox keychain for tests; it guards nothing
        var made: SecKeychain?
        var status: OSStatus
        if FileManager.default.fileExists(atPath: file.path) {
            status = SecKeychainOpen(file.path, &made)
            if status == errSecSuccess, let made { status = SecKeychainUnlock(made, UInt32(pass.utf8.count), pass, true) }
        } else {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            status = SecKeychainCreate(file.path, UInt32(pass.utf8.count), pass, false, nil, &made)
        }
        guard status == errSecSuccess, let made else { throw KeychainError(status: status) }
        keychain = made
    }

    private func query(_ id: String) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: Self.service,
                                kSecAttrAccount as String: id]
        if let keychain { q[kSecMatchSearchList as String] = [keychain] }
        return q
    }

    public func hasPassword(for id: String) -> Bool {
        SecItemCopyMatching(query(id) as CFDictionary, nil) == errSecSuccess
    }

    public func password(for id: String) -> String? {
        var q = query(id)
        q[kSecReturnData as String] = true
        var data: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &data) == errSecSuccess, let data = data as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func setPassword(_ password: String, for id: String, label: String) throws {
        let values: [String: Any] = [kSecValueData as String: Data(password.utf8), kSecAttrLabel as String: label]
        var status = SecItemUpdate(query(id) as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            var add = query(id)
            add.removeValue(forKey: kSecMatchSearchList as String)
            if let keychain { add[kSecUseKeychain as String] = keychain }
            add[kSecAttrDescription as String] = "Luksfer network drive password"
            add.merge(values) { $1 }
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    public func removePassword(for id: String) {
        SecItemDelete(query(id) as CFDictionary)
    }
}
