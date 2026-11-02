import XCTest
@testable import LuksferCore

final class ShellLaunchPlanTests: XCTestCase {
    private func env(_ plan: ShellLaunchPlan) -> [String: String] {
        var out: [String: String] = [:]
        for entry in plan.environment {
            let parts = entry.split(separator: "=", maxSplits: 1).map(String.init)
            XCTAssertNil(out[parts[0]], "\(parts[0]) twice")
            out[parts[0]] = parts.count > 1 ? parts[1] : ""
        }
        return out
    }

    private let base = ["TERM=xterm-256color", "COLORTERM=truecolor", "LANG=en_US.UTF-8", "HOME=/old"]

    func testZshGetsTheIntegration() {
        let plan = ShellLaunchPlan.make(accountShell: "/bin/zsh", isExecutable: { _ in true }, base: base,
                                        processEnvironment: ["PATH": "/usr/bin:/bin", "ZDOTDIR": "/z",
                                                             "SSH_AUTH_SOCK": "/sock", "TERM_PROGRAM": "x"],
                                        home: "/Users/u", user: "u", shellFilesFolder: "/luksfer/shell",
                                        sessionKey: "k1")
        XCTAssertEqual(plan.executable, "/bin/zsh")
        XCTAssertEqual(plan.argv0, "-zsh")
        XCTAssertTrue(plan.usesZshIntegration)
        XCTAssertEqual(plan.sessionKey, "k1")
        let e = env(plan)
        XCTAssertEqual(e["LUKSFER_SESSION_KEY"], "k1")
        XCTAssertEqual(e["ZDOTDIR"], "/luksfer/shell")
        XCTAssertEqual(e["LUKSFER_USER_ZDOTDIR"], "/z")
        XCTAssertEqual(e["LUKSFER_ZDOTDIR_EXPORTED"], "1")
        XCTAssertEqual(e["TERM"], "xterm-256color")
        XCTAssertEqual(e["TERM_PROGRAM"], "Luksfer")
        XCTAssertEqual(e["COLORTERM"], "truecolor")
        XCTAssertEqual(e["HOME"], "/Users/u")
        XCTAssertEqual(e["USER"], "u")
        XCTAssertEqual(e["LOGNAME"], "u")
        XCTAssertEqual(e["SHELL"], "/bin/zsh")
        XCTAssertEqual(e["PATH"], "/usr/bin:/bin")
        XCTAssertEqual(e["SSH_AUTH_SOCK"], "/sock")
        XCTAssertEqual(e["LANG"], "en_US.UTF-8")
    }

    func testUserZdotdirDefaultsToHome() {
        let plan = ShellLaunchPlan.make(accountShell: "/opt/homebrew/bin/zsh", isExecutable: { _ in true },
                                        base: base, processEnvironment: [:], home: "/Users/u", user: "u",
                                        shellFilesFolder: "/luksfer/shell")
        let e = env(plan)
        XCTAssertEqual(e["LUKSFER_USER_ZDOTDIR"], "/Users/u")
        XCTAssertNil(e["LUKSFER_ZDOTDIR_EXPORTED"])
        XCTAssertEqual(e["PATH"], ShellLaunchPlan.fallbackPath)
    }

    func testKeepsTheUsersLanguage() {
        let plan = ShellLaunchPlan.make(accountShell: "/bin/zsh", isExecutable: { _ in true }, base: base,
                                        processEnvironment: ["LANG": "pl_PL.UTF-8"], home: "/h", user: "u",
                                        shellFilesFolder: "/s")
        XCTAssertEqual(env(plan)["LANG"], "pl_PL.UTF-8")
        let noLang = ShellLaunchPlan.make(accountShell: "/bin/zsh", isExecutable: { _ in true }, base: [],
                                          processEnvironment: [:], home: "/h", user: "u", shellFilesFolder: "/s")
        XCTAssertEqual(env(noLang)["LANG"], "en_US.UTF-8")
    }

    func testOtherShellsRunWithoutTheIntegration() {
        let plan = ShellLaunchPlan.make(accountShell: "/opt/homebrew/bin/fish", isExecutable: { _ in true },
                                        base: base + ["ZDOTDIR=/leak"], processEnvironment: ["ZDOTDIR": "/z"],
                                        home: "/h", user: "u", shellFilesFolder: "/s")
        XCTAssertEqual(plan.argv0, "-fish")
        XCTAssertFalse(plan.usesZshIntegration)
        XCTAssertNil(env(plan)["ZDOTDIR"])
        XCTAssertNil(env(plan)["LUKSFER_USER_ZDOTDIR"])
        XCTAssertNil(plan.sessionKey)
        XCTAssertNil(env(plan)["LUKSFER_SESSION_KEY"])
    }

    func testFallsBackToZsh() {
        for shell in [nil, "", "/missing/shell"] as [String?] {
            let plan = ShellLaunchPlan.make(accountShell: shell, isExecutable: { $0 == "/bin/zsh" },
                                            base: base, processEnvironment: [:], home: "/h", user: "u",
                                            shellFilesFolder: "/s")
            XCTAssertEqual(plan.executable, "/bin/zsh")
            XCTAssertEqual(env(plan)["SHELL"], "/bin/zsh")
        }
    }

    func testNoFilesFolderMeansNoIntegration() {
        let plan = ShellLaunchPlan.make(accountShell: "/bin/zsh", isExecutable: { _ in true }, base: base,
                                        processEnvironment: [:], home: "/h", user: "u", shellFilesFolder: nil)
        XCTAssertFalse(plan.usesZshIntegration)
        XCTAssertNil(env(plan)["ZDOTDIR"])
    }
}

final class ShellTerminalAppTests: XCTestCase {
    func testNamesAndBundles() {
        XCTAssertEqual(TerminalApp.allCases.map(\.displayName), ["Terminal", "iTerm2", "Ghostty", "Warp"])
        XCTAssertEqual(TerminalApp.ghostty.bundleIdentifier, "com.mitchellh.ghostty")
        XCTAssertEqual(TerminalApp(rawValue: "iterm2"), .iterm2)
    }

    func testCodable() throws {
        let data = try JSONEncoder().encode([TerminalApp.warp])
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"["warp"]"#)
        XCTAssertEqual(try JSONDecoder().decode([TerminalApp].self, from: data), [.warp])
    }

    func testLaunchURLs() {
        let folder = URL(fileURLWithPath: "/a b/c&d+e#f?g=h", isDirectory: true)
        for app in [TerminalApp.terminal, .iterm2, .ghostty] {
            XCTAssertEqual(app.launchURL(forFolder: folder), folder)
        }
        XCTAssertEqual(TerminalApp.warp.launchURL(forFolder: folder).absoluteString,
                       "warp://action/new_window?path=/a%20b/c%26d%2Be%23f%3Fg%3Dh")
        // Non-ASCII names: every byte encoded, and the query decodes back to the path.
        let unicode = URL(fileURLWithPath: "/zażółć/文件", isDirectory: true)
        let query = TerminalApp.warp.launchURL(forFolder: unicode).query ?? ""
        XCTAssertTrue(query.allSatisfy(\.isASCII), query)
        XCTAssertEqual(query.dropFirst("path=".count).removingPercentEncoding, unicode.path)
    }
}
