import Foundation

/// A private OSC 6973 mark from Luksfer's zsh integration.
public enum ShellMark: String, Sendable {
    /// The line editor started on an empty main prompt, nothing typed ahead.
    case prompt
    /// The line editor started with text on the line, typed ahead, or on a continuation line.
    case promptTyped = "prompt-typed"
    /// A command started.
    case exec

    public init?(payload: String) { self.init(rawValue: payload) }
}

/// A report from Luksfer's zsh integration: the payload of `OSC 6973 ; <session key> ; <report>`.
public enum ShellReport: Equatable, Sendable {
    case mark(ShellMark)
    /// The folder as a file URL, read with `OSC7`.
    case folder(String)

    /// Nil without the right session key: anything a program prints reaches the terminal too.
    public init?(payload: String, key: String) {
        let parts = payload.split(separator: ";", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2, !key.isEmpty, parts[0] == key else { return nil }
        if parts[1] == "folder", parts.count == 3 {
            self = .folder(parts[2])
        } else if parts.count == 2, let mark = ShellMark(payload: parts[1]) {
            self = .mark(mark)
        } else {
            return nil
        }
    }
}

/// What the terminal panel knows about its shell: the folder, and whether it waits at an empty
/// prompt. Pure state: the panel feeds it the shell's marks and the user's input, and acts on
/// what it returns.
///
/// Idle means a `prompt` mark arrived and the user has not typed since. Luksfer moves the shell
/// only when idle (`ZshIntegration.followKeys(to:)`). A folder asked for while Luksfer's own move
/// still runs waits for the next prompt.
public struct ShellSessionState: Equatable, Sendable {
    /// The shell waits at an empty prompt and nothing was typed since.
    public private(set) var isIdle = false
    /// The last folder the shell reported.
    public private(set) var folder: URL?
    /// Path of the move Luksfer sent, until the next prompt.
    private var sentPath: String?
    /// Path asked for while Luksfer's own move ran.
    private var queuedPath: String?

    public init() {}

    /// The answer to `request(_:)`.
    public enum Request: Equatable, Sendable {
        /// Send this text now (the Follow keys).
        case send(String)
        /// Luksfer's previous move still runs; this one follows at the next prompt.
        case queued
        /// The shell is there already, or on its way.
        case alreadyThere
        /// The user typed, or a command runs.
        case busy
    }

    /// A folder change the shell reported.
    public enum FolderChange: Equatable, Sendable {
        /// The user moved the shell (typed `cd`, ran a script...).
        case user(URL)
        /// The result of a move Luksfer sent.
        case own(URL)
    }

    /// Asks to move the shell to `folder`.
    public mutating func request(_ folder: URL) -> Request {
        let path = Self.path(of: folder)
        if let sent = sentPath {
            queuedPath = path == sent ? nil : path
            return path == sent ? .alreadyThere : .queued
        }
        if let current = self.folder, Self.path(of: current) == path { return .alreadyThere }
        guard isIdle else { return .busy }
        return send(path)
    }

    /// A mark arrived. Returns text to send now (a queued move), if any.
    public mutating func received(_ mark: ShellMark) -> String? {
        switch mark {
        case .prompt:
            sentPath = nil
            isIdle = true
            if let queued = queuedPath {
                queuedPath = nil
                if let current = folder, Self.path(of: current) == queued { return nil }
                if case .send(let line) = send(queued) { return line }
            }
        case .promptTyped:
            sentPath = nil
            queuedPath = nil
            isIdle = false
        case .exec:
            isIdle = false
        }
        return nil
    }

    /// The shell reported `folder`. Nil when it is the same folder as before.
    public mutating func reported(folder url: URL) -> FolderChange? {
        let path = Self.path(of: url)
        if let current = folder, Self.path(of: current) == path { return nil }
        let clean = URL(fileURLWithPath: path, isDirectory: true)
        folder = clean
        return path == sentPath ? .own(clean) : .user(clean)
    }

    /// The user typed, pasted or pressed a key in the terminal.
    public mutating func userInput() {
        isIdle = false
        queuedPath = nil
    }

    /// A new shell starts, or the old one exited.
    public mutating func reset() { self = ShellSessionState() }

    private mutating func send(_ path: String) -> Request {
        isIdle = false
        sentPath = path
        return .send(ZshIntegration.followKeys(to: path))
    }

    /// The path without a trailing slash ("/" stays "/").
    static func path(of url: URL) -> String {
        var path = url.path
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        return path.isEmpty ? "/" : path
    }
}
