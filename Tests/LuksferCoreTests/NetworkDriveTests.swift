import XCTest
@testable import LuksferCore

final class NetworkDriveTests: XCTestCase {
    func testAddressForms() {
        let plain = SMBAddress(host: "nas.local", share: "Photos")
        XCTAssertEqual(SMBAddress.parse("smb://nas.local/Photos"), plain)
        XCTAssertEqual(SMBAddress.parse("SMB://nas.local/Photos/"), plain)
        XCTAssertEqual(SMBAddress.parse(#"\\nas.local\Photos"#), plain)
        XCTAssertEqual(SMBAddress.parse("  nas.local/Photos  "), plain)
        XCTAssertEqual(SMBAddress.parse("//nas.local/Photos"), plain)

        XCTAssertEqual(SMBAddress.parse(#"\\nas.local\Photos\2024\Trip"#),
                       SMBAddress(host: "nas.local", share: "Photos", folder: "2024/Trip"))
        XCTAssertEqual(SMBAddress.parse("smb://anna@192.0.2.20:4445/Team%20Files"),
                       SMBAddress(host: "192.0.2.20", port: 4445, share: "Team Files", user: "anna"))
        XCTAssertEqual(SMBAddress.parse("smb://nas/My Share"), SMBAddress(host: "nas", share: "My Share"))
        XCTAssertEqual(SMBAddress.parse("smb://[fe80::1]:445/data"), SMBAddress(host: "[fe80::1]", port: 445, share: "data"))
        XCTAssertEqual(SMBAddress.parse("smb://OFFICE;anna@nas/data")?.user, "OFFICE;anna")
    }

    func testBadAddresses() {
        for text in ["", "nas.local", "smb://nas.local", "smb:///Photos", "afp://nas/Photos", "nfs://nas/export",
                     "smb://nas:0/Photos", "smb://nas:99999/Photos", "smb://nas:abc/Photos", "smb://my nas/Photos",
                     "smb://[fe80::1/data"] {
            XCTAssertNil(SMBAddress.parse(text), text)
        }
    }

    func testPasswordInTheAddressIsDropped() throws {
        let address = try XCTUnwrap(SMBAddress.parse("smb://anna:hunter2@nas/data"))
        XCTAssertEqual(address.user, "anna")
        XCTAssertFalse(address.text.contains("hunter2"))
        XCTAssertFalse(address.shareURL.absoluteString.contains("hunter2"))
        XCTAssertFalse(address.shareURL.absoluteString.contains("anna"))
    }

    func testTextAndShareURL() throws {
        let address = try XCTUnwrap(SMBAddress.parse(#"\\nas\Team Files\Plans"#))
        XCTAssertEqual(address.text, "smb://nas/Team Files/Plans")
        XCTAssertEqual(address.shareURL.absoluteString, "smb://nas/Team%20Files")
        XCTAssertEqual(SMBAddress.parse(address.text), address)
        XCTAssertEqual(SMBAddress.parse("smb://nas:4445/x")?.shareURL.absoluteString, "smb://nas:4445/x")
    }

    func testMountMatching() throws {
        let address = try XCTUnwrap(SMBAddress.parse("smb://NAS.local/photos/2024"))
        let mount = NetworkMount(mountPoint: URL(fileURLWithPath: "/Volumes/Photos"), source: "//anna@nas.local/Photos", fileSystem: "smbfs")
        XCTAssertTrue(mount.isMount(of: address))
        XCTAssertEqual(mount.folder(for: address).path, "/Volumes/Photos/2024")
        let other = NetworkMount(mountPoint: URL(fileURLWithPath: "/Volumes/Music"), source: "//nas.local/Music", fileSystem: "smbfs")
        XCTAssertFalse(other.isMount(of: address))
        let afp = NetworkMount(mountPoint: URL(fileURLWithPath: "/Volumes/Photos"), source: "afp://nas.local/Photos", fileSystem: "afpfs")
        XCTAssertFalse(afp.isMount(of: address))
    }

    func testCurrentMountsAreNetworkOnly() {
        // Reads the real mount table without waiting; the start disk is never in it.
        XCTAssertFalse(NetworkMount.current().contains { $0.mountPoint.path == "/" })
        XCTAssertTrue(NetworkMount.current().allSatisfy { NetworkMount.networkFileSystems.contains($0.fileSystem) })
    }

    func testSettingsKeepDrivesWithoutPasswords() throws {
        let box = CoreSandbox()
        let store = SettingsStore(folder: box.root, home: box.folder("home"))
        let drive = NetworkDrive(name: "Photos", address: "smb://nas/Photos", user: "anna")
        store.update { $0.networkDrives = [drive] }
        store.saveNow()
        XCTAssertEqual(SettingsStore(folder: box.root, home: box.root).settings.networkDrives, [drive])
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: store.fileURL)) as? [String: Any]
        let saved = try XCTUnwrap(json?["networkDrives"] as? [[String: Any]])
        XCTAssertEqual(saved.first.map { Set($0.keys) }, ["id", "name", "address", "user"])
        // Older settings files have no drives.
        try Data(#"{"showHidden": true}"#.utf8).write(to: store.fileURL)
        XCTAssertEqual(SettingsStore(folder: box.root, home: box.root).settings.networkDrives, [])
    }

    func testKeychainStoreInASandboxKeychain() throws {
        let box = CoreSandbox()
        let listBefore = try keychainList()
        let store = try KeychainPasswordStore(file: box.root.appendingPathComponent("test.keychain-db"))
        let id = "test-\(UUID().uuidString)"
        XCTAssertFalse(store.hasPassword(for: id))
        XCTAssertNil(store.password(for: id))

        try store.setPassword("first secret", for: id, label: "Luksfer: smb://nas/Photos")
        XCTAssertTrue(store.hasPassword(for: id))
        XCTAssertEqual(store.password(for: id), "first secret")
        try store.setPassword("second secret", for: id, label: "Luksfer: smb://nas/Photos")
        XCTAssertEqual(store.password(for: id), "second secret")

        // The item is in the sandbox keychain only, and the user's keychain list stays the same.
        XCTAssertFalse(KeychainPasswordStore().hasPassword(for: id))
        XCTAssertEqual(try keychainList(), listBefore)

        // Opening the same file again finds the item.
        let again = try KeychainPasswordStore(file: box.root.appendingPathComponent("test.keychain-db"))
        XCTAssertEqual(again.password(for: id), "second secret")

        store.removePassword(for: id)
        XCTAssertFalse(store.hasPassword(for: id))
        XCTAssertNil(again.password(for: id))
    }

    private func keychainList() throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["list-keychains", "-d", "user"]
        let out = Pipe()
        p.standardOutput = out
        try p.run()
        p.waitUntilExit()
        return String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }
}
