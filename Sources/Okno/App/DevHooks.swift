import AppKit

/// Switches for test runs, read from the environment. Unused in normal use.
///   OKNO_OPEN=<folder>       open one window at this folder instead of the saved windows
///   OKNO_SNAPSHOT=<png>      after OKNO_SNAPSHOT_DELAY seconds (default 2), draw the key window into a PNG
///   OKNO_SNAPSHOT_QUIT=1     quit after the snapshot
///   OKNO_SETTINGS_DIR=<dir>  settings folder (see AppServices)
///   OKNO_BENCH=<folder>      1 s after launch, open this folder in the active pane three times
///                            (with OKNO_TRACE=1 the list prints how long each open took)
enum DevHooks {
    private static let env = ProcessInfo.processInfo.environment

    static var openFolder: URL? { env["OKNO_OPEN"].map { URL(fileURLWithPath: $0, isDirectory: true) } }

    static func scheduleBench() {
        guard let path = env["OKNO_BENCH"] else { return }
        let target = URL(fileURLWithPath: path, isDirectory: true)
        for i in 0..<3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1 + Double(i) * 1.5) {
                guard let c = NSApp.windows.compactMap({ $0.windowController as? BrowserWindowController }).first else { return }
                c.activePane.navigate(to: target.deletingLastPathComponent())
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { c.activePane.navigate(to: target) }
            }
        }
    }

    static func scheduleSnapshot() {
        guard let path = env["OKNO_SNAPSHOT"] else { return }
        let delay = Double(env["OKNO_SNAPSHOT_DELAY"] ?? "") ?? 2
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            snapshot(to: URL(fileURLWithPath: path))
            if env["OKNO_SNAPSHOT_QUIT"] == "1" { NSApp.terminate(nil) }
        }
    }

    /// Draws the whole window (title bar and toolbar included) without screen-recording access.
    /// The window's real screen pixels (an app may grab its own windows without a permission).
    /// `cacheDisplay` misses the terminal's text, so the self-test uses this for the terminal.
    static func grab(_ window: NSWindow, to url: URL) {
        typealias Grab = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        // CGWindowListCreateImage is hidden from the macOS 15 SDK; look it up by name.
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage"),
              let image = unsafeBitCast(sym, to: Grab.self)(.null, 8 /* including window */,
                                                           UInt32(window.windowNumber), 1 | 8 /* no frame, best resolution */)?.takeRetainedValue()
        else { return }
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
    }

    static func snapshot(to url: URL) {
        guard let window = NSApp.windows.first(where: { $0.windowController is BrowserWindowController }),
              let frameView = window.contentView?.superview,
              let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else { return }
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
