import XCTest
@testable import OknoCore

final class PathResolverTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/alex", isDirectory: true)
    private let base = URL(fileURLWithPath: "/Users/alex/Projects", isDirectory: true)

    private func expand(_ text: String) -> String {
        PathResolver.expand(text, relativeTo: base, home: home)
    }

    // MARK: - expand

    func testTilde() {
        XCTAssertEqual(expand("~"), "/Users/alex")
        XCTAssertEqual(expand("~/"), "/Users/alex")
        XCTAssertEqual(expand("~/Documents"), "/Users/alex/Documents")
        XCTAssertEqual(expand("~root"), "/var/root")
        XCTAssertEqual(expand("~no-such-user-here/x"), "/Users/alex/Projects/~no-such-user-here/x")
    }

    func testAbsolutePathsAndSlashes() {
        XCTAssertEqual(expand("/"), "/")
        XCTAssertEqual(expand("/Applications"), "/Applications")
        XCTAssertEqual(expand("/Users/alex/Documents/"), "/Users/alex/Documents")
        XCTAssertEqual(expand("//Users///alex//Documents//"), "/Users/alex/Documents")
    }

    func testWhitespaceAndNewlinesAreTrimmed() {
        XCTAssertEqual(expand("  ~/Documents \n"), "/Users/alex/Documents")
    }

    func testQuotes() {
        XCTAssertEqual(expand("'/Users/alex/My Folder'"), "/Users/alex/My Folder")
        XCTAssertEqual(expand("\"~/My Folder/\""), "/Users/alex/My Folder")
        XCTAssertEqual(expand("“/Users/alex/Notes”"), "/Users/alex/Notes")
        XCTAssertEqual(expand("'/Users/alex/Half typed"), "/Users/alex/Half typed")
    }

    func testBackslashEscapesFromATerminal() {
        XCTAssertEqual(expand("/Users/alex/My\\ Folder/Report\\ \\(1\\).txt"),
                       "/Users/alex/My Folder/Report (1).txt")
        XCTAssertEqual(expand("~/It\\'s\\ here"), "/Users/alex/It's here")
        // Inside single quotes a backslash is a plain character, as in the shell.
        XCTAssertEqual(expand("'/Users/alex/a\\ b'"), "/Users/alex/a\\ b")
        // Inside double quotes only \" \\ \$ \` are escapes.
        XCTAssertEqual(expand("\"/Users/alex/say \\\"hi\\\" \\n\""), "/Users/alex/say \"hi\" \\n")
    }

    func testRelativePaths() {
        XCTAssertEqual(expand("Okno"), "/Users/alex/Projects/Okno")
        XCTAssertEqual(expand("Okno/Sources/"), "/Users/alex/Projects/Okno/Sources")
        XCTAssertEqual(expand("."), "/Users/alex/Projects")
        XCTAssertEqual(expand("./Okno"), "/Users/alex/Projects/Okno")
        XCTAssertEqual(expand(".."), "/Users/alex")
        XCTAssertEqual(expand("../Documents/./Letters/../Notes"), "/Users/alex/Documents/Notes")
        XCTAssertEqual(expand("/../../.."), "/")
        XCTAssertEqual(expand(""), "/Users/alex/Projects")
    }

    func testFileURLs() {
        XCTAssertEqual(expand("file:///Users/alex/My%20Folder/"), "/Users/alex/My Folder")
        XCTAssertEqual(expand("file://localhost/Users/alex/Notes"), "/Users/alex/Notes")
        XCTAssertEqual(expand("'file:///Users/alex/a%20b.txt'"), "/Users/alex/a b.txt")
    }

    func testAbbreviate() {
        XCTAssertEqual(PathResolver.abbreviate("/Users/alex", home: home), "~")
        XCTAssertEqual(PathResolver.abbreviate("/Users/alex/foo", home: home), "~/foo")
        XCTAssertEqual(PathResolver.abbreviate("/Users/alexandra", home: home), "/Users/alexandra")
        XCTAssertEqual(PathResolver.abbreviate("/tmp", home: home), "/tmp")
    }

    // MARK: - resolve (sandbox on disk)

    func testResolveFolderFileAndPackage() throws {
        let sandbox = try PathSandbox()
        defer { sandbox.remove() }
        let projects = try sandbox.folder("Projects")
        let notes = try sandbox.file("Projects/notes.txt")
        let tool = try sandbox.folder("Projects/Tool.app")
        let root = sandbox.root

        func resolve(_ text: String) -> PathInput {
            PathResolver.resolve(text, relativeTo: root, home: root)
        }
        XCTAssertEqual(resolve("Projects"), .folder(URL(fileURLWithPath: projects.path, isDirectory: true)))
        XCTAssertEqual(resolve("~/Projects/"), .folder(URL(fileURLWithPath: projects.path, isDirectory: true)))
        XCTAssertEqual(resolve("'" + projects.path + "'"), .folder(URL(fileURLWithPath: projects.path, isDirectory: true)))
        XCTAssertEqual(resolve("Projects/../Projects/notes.txt"), .file(URL(fileURLWithPath: notes.path, isDirectory: false)))
        XCTAssertEqual(resolve("~/Projects/Tool.app"), .file(URL(fileURLWithPath: tool.path, isDirectory: true)))
        XCTAssertEqual(resolve(projects.absoluteString), .folder(URL(fileURLWithPath: projects.path, isDirectory: true)))
    }

    func testResolveMissingGivesAMessage() throws {
        let sandbox = try PathSandbox()
        defer { sandbox.remove() }
        let root = sandbox.root
        XCTAssertEqual(PathResolver.resolve("~/nope", relativeTo: root, home: root),
                       .notFound("No folder or file at ~/nope"))
        XCTAssertEqual(PathResolver.resolve("missing/part", relativeTo: root, home: root),
                       .notFound("No folder or file at ~/missing/part"))
        XCTAssertEqual(PathResolver.resolve("/no-such-folder-okno", relativeTo: root, home: root),
                       .notFound("No folder or file at /no-such-folder-okno"))
    }

    func testResolveBrokenLinkIsAFile() throws {
        let sandbox = try PathSandbox()
        defer { sandbox.remove() }
        let link = sandbox.root.appendingPathComponent("Dangling")
        XCTAssertEqual(symlink(sandbox.root.appendingPathComponent("Gone").path, link.path), 0)
        XCTAssertEqual(PathResolver.resolve("Dangling", relativeTo: sandbox.root),
                       .file(URL(fileURLWithPath: link.path, isDirectory: false)))
    }

    func testTerminalWords() {
        for word in ["term", "terminal", "cmd", " Term ", "CMD", "Terminal\n"] {
            XCTAssertEqual(PathResolver.resolve(word, relativeTo: base, home: home), .openTerminal, word)
        }
        XCTAssertNotEqual(PathResolver.resolve("terminals", relativeTo: base, home: home), .openTerminal)
        XCTAssertNotEqual(PathResolver.resolve("./term", relativeTo: base, home: home), .openTerminal)
    }
}
