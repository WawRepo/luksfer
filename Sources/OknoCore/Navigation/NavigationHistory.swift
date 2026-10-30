import Foundation

/// Back and forward history of one pane.
public struct NavigationHistory: Equatable, Sendable {
    public private(set) var current: URL
    private var back: [URL] = []
    private var forward: [URL] = []

    public init(start: URL) { current = start }

    public var canGoBack: Bool { !back.isEmpty }
    public var canGoForward: Bool { !forward.isEmpty }
    public var backList: [URL] { back.reversed() }
    public var forwardList: [URL] { forward.reversed() }

    /// Opens a new folder: it becomes current and the forward list is cleared.
    public mutating func visit(_ url: URL) {
        guard url.standardizedFileURL != current.standardizedFileURL else { return }
        back.append(current)
        if back.count > 100 { back.removeFirst() }
        forward.removeAll()
        current = url
    }

    @discardableResult public mutating func goBack() -> URL? {
        guard let url = back.popLast() else { return nil }
        forward.append(current)
        current = url
        return url
    }

    @discardableResult public mutating func goForward() -> URL? {
        guard let url = forward.popLast() else { return nil }
        back.append(current)
        current = url
        return url
    }
}
