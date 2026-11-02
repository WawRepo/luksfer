import Foundation

/// Environment switches for test runs that change where deletes, passwords or mounts go. They count
/// only together with a self-test mode, and every mode ends by quitting the app, so nobody can work
/// in a session whose deletes go to a plain folder or whose passwords go to a test keychain.
public enum TestSwitches {
    /// The values of `LUKSFER_SELFTEST` that run a test.
    public static let selfTestModes: Set<String> = ["1", "restore", "opened"]

    public static func isSelfTest(in environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        environment["LUKSFER_SELFTEST"].map(selfTestModes.contains) ?? false
    }

    public static func selfTestOnly(_ name: String,
                                    in environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        isSelfTest(in: environment) ? environment[name] : nil
    }
}
