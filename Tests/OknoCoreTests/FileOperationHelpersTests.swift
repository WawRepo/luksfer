import Darwin
import XCTest
@testable import OknoCore

/// Base class for file operation tests. Each test gets its own sandbox under
/// ~/Library/Caches/okno-dev/sandbox/fileops-tests/<uuid>/ with a `root` folder to work in and
/// a `Trash` folder the engine trashes into. The real Trash is never used.
class FileOperationTestCase: XCTestCase {
    var sandbox: URL!
    var root: URL!
    var trashFolder: URL!
    var engine: FileOperationEngine!
    let fm = FileManager.default

    override func setUpWithError() throws {
        let base = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/okno-dev/sandbox/fileops-tests", isDirectory: true)
        sandbox = base.appendingPathComponent(UUID().uuidString, isDirectory: true)
        root = sandbox.appendingPathComponent("root", isDirectory: true)
        trashFolder = sandbox.appendingPathComponent("Trash", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try fm.createDirectory(at: trashFolder, withIntermediateDirectories: true)
        engine = FileOperationEngine(trasher: FolderTrasher(folder: trashFolder))
    }

    override func tearDownWithError() throws {
        // Only ever remove our own sandbox.
        guard let sandbox, sandbox.path.contains("/okno-dev/sandbox/fileops-tests/") else { return }
        try? fm.removeItem(at: sandbox)
    }

    // MARK: Making items

    func url(_ relative: String, isFolder: Bool = false) -> URL {
        root.appendingPathComponent(relative, isDirectory: isFolder)
    }

    @discardableResult
    func file(_ relative: String, _ text: String = "text") throws -> URL {
        try data(relative, Data(text.utf8))
    }

    @discardableResult
    func data(_ relative: String, _ contents: Data) throws -> URL {
        let target = url(relative)
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: target)
        return target
    }

    /// A file of `megabytes` MiB of non-zero bytes.
    @discardableResult
    func bigFile(_ relative: String, megabytes: Int) throws -> URL {
        let target = url(relative)
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        fm.createFile(atPath: target.path, contents: nil)
        let handle = try FileHandle(forWritingTo: target)
        let chunk = Data((0..<(1 << 20)).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) })
        for _ in 0..<megabytes { try handle.write(contentsOf: chunk) }
        try handle.close()
        return target
    }

    @discardableResult
    func folder(_ relative: String) throws -> URL {
        let target = url(relative, isFolder: true)
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        return target
    }

    @discardableResult
    func link(_ relative: String, to destination: String) throws -> URL {
        let target = url(relative)
        try fm.createSymbolicLink(atPath: target.path, withDestinationPath: destination)
        return target
    }

    // MARK: Looking

    enum Entry: Equatable, CustomStringConvertible {
        case folder, file(Data), link(String)
        var description: String {
            switch self {
            case .folder: return "folder"
            case .file(let data): return "file(\(String(decoding: data.prefix(40), as: UTF8.self)), \(data.count) B)"
            case .link(let target): return "link(\(target))"
            }
        }
    }

    /// Every item under `folder` (default `root`): relative path → kind and contents.
    func snapshot(_ folder: URL? = nil) throws -> [String: Entry] {
        var result: [String: Entry] = [:]
        func walk(_ dir: URL, _ prefix: String) throws {
            for name in try fm.contentsOfDirectory(atPath: dir.path) {
                let child = dir.appendingPathComponent(name)
                let relative = prefix.isEmpty ? name : prefix + "/" + name
                let type = try fm.attributesOfItem(atPath: child.path)[.type] as? FileAttributeType
                switch type {
                case .typeSymbolicLink: result[relative] = .link(try fm.destinationOfSymbolicLink(atPath: child.path))
                case .typeDirectory:
                    result[relative] = .folder
                    try walk(child, relative)
                default: result[relative] = .file(try Data(contentsOf: child))
                }
            }
        }
        try walk(folder ?? root, "")
        return result
    }

    /// Names in a folder, hidden ones included, sorted.
    func names(_ folder: URL? = nil) throws -> [String] {
        try fm.contentsOfDirectory(atPath: (folder ?? root).path).sorted()
    }

    func trashNames() throws -> [String] { try names(trashFolder) }

    func text(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }

    func inode(_ url: URL) -> ino_t? { FileSystem.info(url)?.id.inode }

    func isCaseInsensitiveVolume() throws -> Bool {
        try root.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]).volumeSupportsCaseSensitiveNames == false
    }

    // MARK: Clash answers and progress

    /// Fails the test if a clash is asked.
    let never: FileOperationEngine.ClashResolver = { clash in
        XCTFail("Unexpected clash for \(clash.existing.lastPathComponent)")
        return ClashDecision(choice: .skip)
    }

    /// Undo, redo, undo: the tree must match `before`, `after`, `before`.
    func assertRoundTrip(_ action: () async throws -> FileChange,
                         file: StaticString = #filePath, line: UInt = #line) async throws {
        let before = try snapshot()
        let change = try await action()
        let after = try snapshot()
        XCTAssertNotEqual(before, after, "the action changed nothing", file: file, line: line)
        let redo = try await engine.undo(change)
        XCTAssertEqual(try snapshot(), before, "undo", file: file, line: line)
        XCTAssertEqual(redo.actionName, change.actionName, file: file, line: line)
        let again = try await engine.undo(redo)
        XCTAssertEqual(try snapshot(), after, "redo", file: file, line: line)
        _ = try await engine.undo(again)
        XCTAssertEqual(try snapshot(), before, "second undo", file: file, line: line)
    }

    /// Runs `body` and returns the `FileOperationError` it throws (fails the test if none).
    func operationError(_ body: () async throws -> Void,
                        file: StaticString = #filePath, line: UInt = #line) async -> FileOperationError? {
        do {
            try await body()
            XCTFail("Expected an error", file: file, line: line)
        } catch let error as FileOperationError {
            return error
        } catch {
            XCTFail("Unexpected error \(error)", file: file, line: line)
        }
        return nil
    }
}

/// Records clashes and answers each with the same decision.
final class ClashRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [NameClash] = []
    let decision: ClashDecision

    init(_ choice: ClashChoice, applyToAll: Bool = false) {
        decision = ClashDecision(choice: choice, applyToAll: applyToAll)
    }

    var clashes: [NameClash] { lock.withLock { recorded } }

    var resolver: FileOperationEngine.ClashResolver {
        { clash in
            self.lock.withLock { self.recorded.append(clash) }
            return self.decision
        }
    }
}

/// Records progress reports and the thread they came on.
final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [OperationProgress] = []
    private var onMain = false
    var onReport: (@Sendable (OperationProgress) -> Void)?

    var reports: [OperationProgress] { lock.withLock { recorded } }
    var anyOnMainThread: Bool { lock.withLock { onMain } }

    var handler: FileOperationEngine.ProgressHandler {
        { progress in
            self.lock.withLock {
                self.recorded.append(progress)
                if Thread.isMainThread { self.onMain = true }
            }
            self.onReport?(progress)
        }
    }
}

/// Holds a task so a progress callback can cancel it, even before it is stored.
final class TaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<FileChange, Error>?
    private var wantsCancel = false

    func set(_ task: Task<FileChange, Error>) {
        let cancelNow = lock.withLock { () -> Bool in
            self.task = task
            return wantsCancel
        }
        if cancelNow { task.cancel() }
    }

    func cancel() {
        let task = lock.withLock { () -> Task<FileChange, Error>? in
            wantsCancel = true
            return self.task
        }
        task?.cancel()
    }
}

/// Checks of the helpers and the small pieces under the engine.
final class FileOperationHelpersTests: FileOperationTestCase {
    func testSandboxIsUnderCaches() throws {
        XCTAssertTrue(sandbox.path.contains("/Library/Caches/okno-dev/sandbox/fileops-tests/"))
        XCTAssertEqual(try names(), [])
    }

    func testMaterializationIsAllowedOnlyInsideAndRestored() {
        let type = IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES
        let original = getiopolicy_np(type, IOPOL_SCOPE_THREAD)
        defer { setiopolicy_np(type, IOPOL_SCOPE_THREAD, max(original, 0)) }

        setiopolicy_np(type, IOPOL_SCOPE_THREAD, IOPOL_MATERIALIZE_DATALESS_FILES_OFF)
        let inside = TreeCopier.withDatalessMaterialization { getiopolicy_np(type, IOPOL_SCOPE_THREAD) }
        XCTAssertEqual(inside, IOPOL_MATERIALIZE_DATALESS_FILES_ON)
        XCTAssertEqual(getiopolicy_np(type, IOPOL_SCOPE_THREAD), IOPOL_MATERIALIZE_DATALESS_FILES_OFF)
    }

    func testFolderTrasherKeepsBothNames() throws {
        let a = try file("x/a.txt", "first")
        let b = try file("y/a.txt", "second")
        let trasher = FolderTrasher(folder: trashFolder)
        let first = try trasher.trash(a)
        let second = try trasher.trash(b)
        XCTAssertEqual(first.lastPathComponent, "a.txt")
        XCTAssertEqual(second.lastPathComponent, "a (2).txt")
        XCTAssertEqual(try text(second), "second")
        XCTAssertFalse(fm.fileExists(atPath: a.path))
    }

    func testTouchedFoldersAreNormalized() throws {
        let change = try engine.createFolder(in: root)
        XCTAssertEqual(change.touchedFolders, [URL(fileURLWithPath: root.path, isDirectory: true)])
    }

    func testErrorMessagesAreReadable() {
        XCTAssertEqual(FileOperationError.invalidName("").errorDescription, "A name can't be empty.")
        XCTAssertEqual(FileOperationError.nameTaken("a.txt").errorDescription,
                       "An item named “a.txt” already exists in this folder.")
        XCTAssertNotNil(FileOperationError.intoItself("f").errorDescription)
        XCTAssertNil(FileOperationError.failed("x").partialChange)
    }
}
