import Foundation

/// How the terminal panel starts the user's login shell: the program, argv[0] and environment.
public struct ShellLaunchPlan: Equatable, Sendable {
    public var executable: String
    /// argv[0], `-zsh`: the leading dash makes it a login shell, so /etc/zprofile's path_helper
    /// and the user's .zprofile fix the short PATH an app opened from the Dock gets.
    public var argv0: String
    /// `NAME=value` entries.
    public var environment: [String]
    /// zsh with `ZDOTDIR` pointing at Okno's integration files.
    public var usesZshIntegration: Bool

    public static let fallbackShell = "/bin/zsh"
    public static let fallbackPath = "/usr/bin:/bin:/usr/sbin:/sbin"
    /// Copied from Okno's own environment when set there.
    static let passedThrough = ["LC_ALL", "LC_CTYPE", "SSH_AUTH_SOCK", "TMPDIR", "__CF_USER_TEXT_ENCODING"]

    /// - Parameters:
    ///   - accountShell: the account's shell (`pw_shell`); `/bin/zsh` when empty or not runnable.
    ///   - base: starting entries, SwiftTerm's `Terminal.getEnvironmentVariables(termName:)`.
    ///   - processEnvironment: Okno's own environment.
    ///   - shellFilesFolder: where `ZshIntegration.files()` were written; nil to skip the integration.
    public static func make(accountShell: String?,
                            isExecutable: (String) -> Bool,
                            base: [String],
                            processEnvironment: [String: String],
                            home: String,
                            user: String,
                            shellFilesFolder: String?) -> ShellLaunchPlan {
        var shell = fallbackShell
        if let candidate = accountShell, !candidate.isEmpty, isExecutable(candidate) { shell = candidate }
        let name = (shell as NSString).lastPathComponent
        let zsh = name.hasPrefix("zsh") && shellFilesFolder != nil

        var env = Environment(base)
        env.remove("ZDOTDIR")
        env.set("LANG", processEnvironment["LANG"] ?? env.value("LANG") ?? "en_US.UTF-8")
        for key in passedThrough { if let value = processEnvironment[key] { env.set(key, value) } }
        env.set("TERM_PROGRAM", "Okno")
        env.set("COLORTERM", "truecolor")
        env.set("HOME", home)
        env.set("USER", user)
        env.set("LOGNAME", user)
        env.set("SHELL", shell)
        env.set("PATH", processEnvironment["PATH"] ?? fallbackPath)
        if zsh, let folder = shellFilesFolder {
            env.set("ZDOTDIR", folder)
            env.set("OKNO_USER_ZDOTDIR", processEnvironment["ZDOTDIR"] ?? home)
            if processEnvironment["ZDOTDIR"] != nil { env.set("OKNO_ZDOTDIR_EXPORTED", "1") }
        }
        return ShellLaunchPlan(executable: shell, argv0: "-" + name,
                               environment: env.entries, usesZshIntegration: zsh)
    }

    /// `NAME=value` entries in order; setting a name again replaces its value in place.
    private struct Environment {
        private(set) var entries: [String] = []

        init(_ entries: [String]) {
            for entry in entries {
                guard let eq = entry.firstIndex(of: "=") else { continue }
                set(String(entry[..<eq]), String(entry[entry.index(after: eq)...]))
            }
        }

        func value(_ name: String) -> String? {
            entries.first { $0.hasPrefix(name + "=") }.map { String($0.dropFirst(name.count + 1)) }
        }

        mutating func set(_ name: String, _ value: String) {
            if let i = entries.firstIndex(where: { $0.hasPrefix(name + "=") }) {
                entries[i] = "\(name)=\(value)"
            } else {
                entries.append("\(name)=\(value)")
            }
        }

        mutating func remove(_ name: String) { entries.removeAll { $0.hasPrefix(name + "=") } }
    }
}
