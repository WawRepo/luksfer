import Foundation
import XCTest
@testable import LuksferCore

final class ShellZshIntegrationTests: XCTestCase {
    func testFiles() {
        XCTAssertEqual(Set(ZshIntegration.files().keys), [".zshenv", ".zprofile", ".zshrc"])
    }

    func testEachFileSourcesTheUsersFileFirst() throws {
        let files = ZshIntegration.files()
        for name in [".zshenv", ".zprofile", ".zshrc"] {
            let text = try XCTUnwrap(files[name])
            XCTAssertTrue(text.contains(#"builtin source "$ZDOTDIR/\#(name)""#), name)
            XCTAssertTrue(text.contains(#"ZDOTDIR="${LUKSFER_USER_ZDOTDIR:-$HOME}""#), name)
        }
        let zshrc = try XCTUnwrap(files[".zshrc"])
        let source = try XCTUnwrap(zshrc.range(of: "builtin source"))
        let hooks = try XCTUnwrap(zshrc.range(of: "add-zsh-hook precmd"))
        XCTAssertLessThan(source.lowerBound, hooks.lowerBound, "hooks come after the user's .zshrc")
    }

    func testZshrcHasTheHooks() throws {
        let zshrc = try XCTUnwrap(ZshIntegration.files()[".zshrc"])
        for needle in [#"\e]7;file://"#, #"\e]6973;prompt\a"#, #"\e]6973;prompt-typed\a"#,
                       #"\e]6973;exec\a"#, "add-zsh-hook precmd __luksfer_precmd",
                       "add-zsh-hook preexec __luksfer_preexec",
                       "add-zle-hook-widget line-init __luksfer_line_init", "is-at-least 5.3",
                       "add-zsh-hook precmd __luksfer_prompt_fallback", "PENDING", "CONTEXT",
                       "add-zsh-hook zshaddhistory", "unset ZDOTDIR", "zle -N __luksfer_follow",
                       #"bindkey -M "$keymap" $'\e[6973~' __luksfer_follow"#, "for keymap in emacs viins vicmd"] {
            XCTAssertTrue(zshrc.contains(needle), needle)
        }
        XCTAssertTrue(zshrc.contains("' builtin cd -- '*"), "history filter matches a typed cd line")
        XCTAssertEqual(ShellMark(payload: "prompt"), .prompt)
        XCTAssertEqual(ShellMark(payload: "prompt-typed"), .promptTyped)
        XCTAssertEqual(ShellMark(payload: "exec"), .exec)
        XCTAssertNil(ShellMark(payload: "nonsense"))
    }

    /// A login, interactive zsh with a made-up user config: the user's files load in zsh's order,
    /// see their own ZDOTDIR, keep top-level variables, and the hooks are installed.
    func testRealZshLoadsUserFilesAndHooks() throws {
        let sandbox = try ShellTestSandbox("zsh-integration")
        defer { sandbox.remove() }
        let files = try sandbox.folder("luksfer-shell")
        let home = try sandbox.folder("home")
        let start = try sandbox.folder("start/a b'c/zażółć")
        for (name, text) in ZshIntegration.files() {
            try text.write(to: files.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        try sandbox.write("order+=(zshenv:$ZDOTDIR)\n", to: "home/.zshenv")
        try sandbox.write("order+=(zprofile:$ZDOTDIR)\ntypeset -U path\nkept=yes\n", to: "home/.zprofile")
        try sandbox.write("order+=(zshrc:$ZDOTDIR)\nsetopt nounset noclobber\n", to: "home/.zshrc")
        try sandbox.write("order+=(zlogin:${ZDOTDIR:-unset})\n", to: "home/.zlogin")

        let script = #"""
        print -r -- "order=${(j:,:)order}"
        print -r -- "kept=$kept zdotdir=${ZDOTDIR-unset} user=${LUKSFER_USER_ZDOTDIR-unset}"
        print -r -- "histfile=$HISTFILE"
        print -r -- "precmd=${(j:,:)precmd_functions} preexec=${(j:,:)preexec_functions}"
        TTY=/dev/stdout
        __luksfer_osc7; print
        if __luksfer_addhistory " builtin cd -- '/x'"$'\n'; then print history=kept; else print history=dropped; fi
        """#
        let out = try runShell("/bin/zsh", ["-l", "-i", "-c", script], environment: [
            "HOME": home.path, "PATH": "/usr/bin:/bin", "TERM": "dumb", "LANG": "en_US.UTF-8",
            "ZDOTDIR": files.path, "LUKSFER_USER_ZDOTDIR": home.path,
        ], in: start)
        let lines = out.split(separator: "\n").map(String.init)
        let h = home.path
        XCTAssertTrue(lines.contains("order=zshenv:\(h),zprofile:\(h),zshrc:\(h),zlogin:unset"), out)
        XCTAssertTrue(lines.contains("kept=yes zdotdir=unset user=unset"), out)
        XCTAssertTrue(lines.contains("histfile=\(h)/.zsh_history"), out)
        XCTAssertTrue(lines.contains("precmd=__luksfer_precmd preexec=__luksfer_preexec"), out)
        XCTAssertTrue(lines.contains("history=dropped"), out)

        let osc = try XCTUnwrap(lines.first { $0.hasPrefix("\u{1B}]7;") }, out)
        XCTAssertTrue(osc.hasSuffix("\u{07}"))
        let payload = String(osc.dropFirst(4).dropLast())
        XCTAssertEqual(OSC7.folder(fromPayload: payload)?.path, start.path)
        XCTAssertTrue(payload.contains("/a%20b%27c/za"), payload)
        XCTAssertTrue(payload.unicodeScalars.allSatisfy(\.isASCII), payload)
    }

    func testFollowKeys() {
        XCTAssertEqual(ZshIntegration.followKeys(to: "/a b"), "\u{1B}[6973~2f612062;")
        let keys = ZshIntegration.followKeys(to: "/x/zażółć\n'$")
        XCTAssertTrue(keys.hasPrefix(ZshIntegration.followKey))
        XCTAssertTrue(keys.dropFirst(ZshIntegration.followKey.count).allSatisfy { $0.isHexDigit || $0 == ";" },
                      "only hex after the key: no Return, quote or control character")
    }

    /// The Follow widget in a real interactive zsh on a pseudo-terminal, with a user config that
    /// uses vi keys, nounset and a chpwd hook that prints: the shell moves to a folder with a hard
    /// name, the prompt mark comes back, and no command line or hook output shows.
    func testRealZshFollowWidget() throws {
        let sandbox = try ShellTestSandbox("zsh-follow")
        defer { sandbox.remove() }
        let files = try sandbox.folder("luksfer-shell")
        let home = try sandbox.folder("home")
        let target = try sandbox.folder("start/a b'c/zażółć $HOME;x")
        for (name, text) in ZshIntegration.files() {
            try text.write(to: files.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        try sandbox.write("PS1='%~ %# '\nbindkey -v\nsetopt nounset\nchpwd() { print HOOK-OUTPUT }\n", to: "home/.zshrc")
        let shell = try PseudoTerminalShell("/bin/zsh", ["-i"], environment: [
            "HOME": home.path, "PATH": "/usr/bin:/bin", "TERM": "xterm-256color", "LANG": "en_US.UTF-8",
            "ZDOTDIR": files.path, "LUKSFER_USER_ZDOTDIR": home.path,
        ], in: home)
        defer { shell.stop() }
        XCTAssertTrue(shell.read(until: "\u{1B}]6973;prompt\u{07}", timeout: 10).contains("6973;prompt"), "first prompt")
        shell.write(ZshIntegration.followKeys(to: target.path))
        let after = shell.read(until: "\u{1B}]6973;prompt\u{07}", timeout: 10)
        XCTAssertTrue(after.contains("6973;prompt\u{07}"), after.debugDescription)
        let osc = try XCTUnwrap(after.components(separatedBy: "\u{1B}]7;").dropFirst().first?.components(separatedBy: "\u{07}").first)
        XCTAssertEqual(OSC7.folder(fromPayload: osc)?.path, target.path)
        XCTAssertFalse(after.contains("builtin"), after.debugDescription)
        XCTAssertFalse(after.contains("HOOK-OUTPUT"), "hook output stays off the screen")
        shell.write("pwd\r")
        XCTAssertTrue(shell.read(until: target.path, timeout: 10).contains(target.path))
    }

    /// A .zshenv that moves ZDOTDIR (a common setup): the other files load from the new folder,
    /// and ZDOTDIR stays a plain (not exported) variable, as in a normal terminal.
    func testRealZshFollowsZdotdirMovedByUserZshenv() throws {
        let sandbox = try ShellTestSandbox("zsh-zdotdir")
        defer { sandbox.remove() }
        let files = try sandbox.folder("luksfer-shell")
        let home = try sandbox.folder("home")
        let config = try sandbox.folder("home/.config/zsh")
        for (name, text) in ZshIntegration.files() {
            try text.write(to: files.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        try sandbox.write("ZDOTDIR=\"$HOME/.config/zsh\"\norder+=(home-zshenv)\n", to: "home/.zshenv")
        try sandbox.write("order+=(zprofile)\n", to: "home/.config/zsh/.zprofile")
        try sandbox.write("order+=(zshrc)\n", to: "home/.config/zsh/.zshrc")
        try sandbox.write("order+=(zlogin:$ZDOTDIR)\n", to: "home/.config/zsh/.zlogin")
        let out = try runShell("/bin/zsh", ["-l", "-i", "-c",
                                            #"print -r -- "${(j:,:)order} ${(t)ZDOTDIR}""#], environment: [
            "HOME": home.path, "PATH": "/usr/bin:/bin", "TERM": "dumb",
            "ZDOTDIR": files.path, "LUKSFER_USER_ZDOTDIR": home.path,
        ])
        XCTAssertEqual(out.trimmingCharacters(in: .newlines),
                       "home-zshenv,zprofile,zshrc,zlogin:\(config.path) scalar")
    }
}

// MARK: - Helpers for the Shell tests

/// A fresh folder under ~/Library/Caches/luksfer-dev/sandbox/terminal/, removed by `remove()`.
struct ShellTestSandbox {
    let root: URL

    init(_ name: String) throws {
        root = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Caches/luksfer-dev/sandbox/terminal", isDirectory: true)
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func folder(_ path: String) throws -> URL {
        let url = root.appendingPathComponent(path, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func write(_ text: String, to path: String) throws {
        try text.write(to: root.appendingPathComponent(path), atomically: true, encoding: .utf8)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

/// A program on a pseudo-terminal (so zsh starts its line editor), for the Follow widget test.
final class PseudoTerminalShell {
    private let process = Process()
    private let master: Int32
    private var buffer = Data()

    init(_ executable: String, _ arguments: [String], environment: [String: String], in directory: URL) throws {
        var master: Int32 = 0, slave: Int32 = 0
        var size = winsize(ws_row: 24, ws_col: 200, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&master, &slave, nil, nil, &size) == 0 else { throw POSIXError(.ENOTTY) }
        self.master = master
        _ = fcntl(master, F_SETFL, fcntl(master, F_GETFL) | O_NONBLOCK)
        let terminal = FileHandle(fileDescriptor: slave, closeOnDealloc: true)
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = directory
        process.standardInput = terminal
        process.standardOutput = terminal
        process.standardError = terminal
        try process.run()
    }

    func write(_ text: String) {
        let bytes = Array(text.utf8)
        _ = bytes.withUnsafeBytes { Darwin.write(master, $0.baseAddress, $0.count) }
    }

    /// Reads until `marker` arrives (or `timeout` seconds pass) and returns what came since the
    /// last read.
    func read(until marker: String, timeout: TimeInterval) -> String {
        let end = Date().addingTimeInterval(timeout)
        var chunk = [UInt8](repeating: 0, count: 65536)
        var text = ""
        while Date() < end {
            let n = Darwin.read(master, &chunk, chunk.count)
            if n > 0 { buffer.append(contentsOf: chunk[0..<n]) } else { usleep(20_000) }
            text = String(decoding: buffer, as: UTF8.self)
            if text.contains(marker) { break }
        }
        buffer.removeAll()
        return text
    }

    func stop() {
        if process.isRunning { process.terminate() }
        close(master)
    }
}

/// Runs a program with exactly `environment` and returns its standard output.
func runShell(_ executable: String, _ arguments: [String], environment: [String: String],
              in directory: URL? = nil) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.environment = environment
    if let directory { process.currentDirectoryURL = directory }
    let out = Pipe()
    process.standardOutput = out
    process.standardError = FileHandle.nullDevice
    process.standardInput = FileHandle.nullDevice
    try process.run()
    let data = out.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(decoding: data, as: UTF8.self)
}
