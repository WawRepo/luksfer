import XCTest
@testable import LuksferCore

final class ShellQuotingTests: XCTestCase {
    func testPlainTextGetsSingleQuotes() {
        XCTAssertEqual(ShellQuoting.singleQuoted("abc"), "'abc'")
        XCTAssertEqual(ShellQuoting.singleQuoted(""), "''")
        XCTAssertEqual(ShellQuoting.singleQuoted("/a b/c d"), "'/a b/c d'")
        XCTAssertEqual(ShellQuoting.singleQuoted("$HOME `x` \"y\" \\ * ? ! ~"), "'$HOME `x` \"y\" \\ * ? ! ~'")
    }

    func testSingleQuotes() {
        XCTAssertEqual(ShellQuoting.singleQuoted("it's"), #"'it'\''s'"#)
        XCTAssertEqual(ShellQuoting.singleQuoted("''"), #"''\'''\'''"#)
    }

    func testUnicodeStaysAsIs() {
        XCTAssertEqual(ShellQuoting.singleQuoted("zażółć 文件 🎉"), "'zażółć 文件 🎉'")
    }

    func testControlCharactersUseANSICQuotes() {
        XCTAssertEqual(ShellQuoting.singleQuoted("a\nb"), #"$'a\nb'"#)
        XCTAssertEqual(ShellQuoting.singleQuoted("a'b\\c!\td"), #"$'a\'b\\c\x21\td'"#)
        XCTAssertEqual(ShellQuoting.singleQuoted("\u{1B}x\u{7F}"), #"$'\x1Bx\x7F'"#)
        XCTAssertEqual(ShellQuoting.singleQuoted("a\u{85}"), #"$'a\xC2\x85'"#)
        for s in ["a\nb", "x\ry", "\u{1B}[31m", "tab\there", "nul\u{0}"] {
            let quoted = ShellQuoting.singleQuoted(s)
            XCTAssertFalse(quoted.unicodeScalars.contains { $0.properties.generalCategory == .control },
                           "raw control character in \(quoted.debugDescription)")
        }
    }

    func testCdCommand() {
        XCTAssertEqual(ShellQuoting.cdCommand(to: "/a b"), " builtin cd -- '/a b'\r")
        XCTAssertTrue(ShellQuoting.cdCommand(to: "/x").hasPrefix(ShellQuoting.cdCommandPrefix))
    }

    /// zsh and bash read every quoted word back as the original text.
    func testRoundTripThroughRealShells() throws {
        let samples = ["plain", "/a b/c", "it's", "''", "zażółć 文件 🎉", "$HOME `id` \"q\" \\n",
                       "a\nb", "line1\nit's\\\n!!", "tab\tend", "\u{1B}[31mred", "a\u{85}b", "-n"]
        for shell in ["/bin/zsh", "/bin/bash"] {
            for sample in samples {
                let script = "printf '%s' \(ShellQuoting.singleQuoted(sample))"
                let flags = shell == "/bin/zsh" ? ["-f", "-c", script] : ["--norc", "--noprofile", "-c", script]
                let out = try runShell(shell, flags, environment: ["LANG": "en_US.UTF-8", "PATH": "/usr/bin:/bin"])
                XCTAssertEqual(out, sample, "\(shell) read \(sample.debugDescription) back wrong")
            }
        }
    }
}
