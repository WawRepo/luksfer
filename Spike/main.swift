// Luksfer spike: measurements and checks that decide the stack.
//
//   swift run LuksferSpike list10k          10,000-item folder: list + fill an NSTableView + scroll pass
//   swift run LuksferSpike drive <folder>   read-only listing of a cloud folder; checks nothing downloads
//   swift run LuksferSpike term             SwiftTerm panel with the login shell, OSC 7 and prompt marks
//   swift run LuksferSpike pasteboard       file URLs on a private pasteboard, as Finder reads them
//
// Every write goes to ~/Library/Caches/luksfer-dev/sandbox/. Real folders are only read.

import AppKit
import SwiftTerm
import UniformTypeIdentifiers

let sandboxRoot = URL(fileURLWithPath: NSHomeDirectory())
    .appendingPathComponent("Library/Caches/luksfer-dev/sandbox", isDirectory: true)

func ms(_ seconds: Double) -> String { String(format: "%.1f ms", seconds * 1000) }

func now() -> Double { ProcessInfo.processInfo.systemUptime }

func median(_ values: [Double]) -> Double {
    let s = values.sorted()
    return s.isEmpty ? 0 : s[s.count / 2]
}

func percentile(_ values: [Double], _ p: Double) -> Double {
    let s = values.sorted()
    return s.isEmpty ? 0 : s[min(s.count - 1, Int(Double(s.count) * p))]
}

// MARK: - Listing (the same keys the app will read)

let listKeys: [URLResourceKey] = [
    .nameKey, .isDirectoryKey, .isPackageKey, .isHiddenKey, .isSymbolicLinkKey,
    .fileSizeKey, .contentModificationDateKey, .creationDateKey, .contentTypeKey,
    .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey,
]

struct Row {
    let name: String
    let isDir: Bool
    let size: Int64
    let modified: Date?
    let type: UTType?
}

var extTypes: [String: UTType] = [:]

// Fast path chosen by the spike: readdir + fstatat, type from the extension (cached).
func listFolder(_ url: URL) throws -> [Row] {
    let raw = listWithStat(url.path)
    var rows: [Row] = []
    rows.reserveCapacity(raw.count)
    for r in raw {
        let ext = (r.name as NSString).pathExtension.lowercased()
        let type: UTType
        if let t = extTypes[ext] { type = t } else { type = UTType(filenameExtension: ext) ?? .data; extTypes[ext] = type }
        let isDir = (r.mode & S_IFMT) == S_IFDIR && !type.conforms(to: .package)
        rows.append(Row(name: r.name, isDir: isDir, size: r.size,
                        modified: Date(timeIntervalSince1970: r.mtime), type: type))
    }
    return rows
}

func sortRows(_ rows: inout [Row]) {
    rows.sort { a, b in
        if a.isDir != b.isDir { return a.isDir }
        return (a.name as NSString).localizedStandardCompare(b.name) == .orderedAscending
    }
}

// MARK: - list10k

final class BenchTable: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var rows: [Row] = []
    var typeNames: [String: String] = [:]
    var icons: [String: NSImage] = [:]
    let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()
    let sizeFormatter = ByteCountFormatter()

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let column = tableColumn else { return nil }
        let id = column.identifier
        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = id
            let text = NSTextField(labelWithString: "")
            text.lineBreakMode = .byTruncatingTail
            text.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(text)
            cell.textField = text
            if id.rawValue == "name" {
                let image = NSImageView()
                image.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(image)
                cell.imageView = image
                NSLayoutConstraint.activate([
                    image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                    image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    image.widthAnchor.constraint(equalToConstant: 16),
                    image.heightAnchor.constraint(equalToConstant: 16),
                    text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 6),
                ])
            } else {
                text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2).isActive = true
            }
            NSLayoutConstraint.activate([
                text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }
        let r = rows[row]
        switch id.rawValue {
        case "name":
            cell.textField?.stringValue = r.name
            cell.imageView?.image = icon(for: r)
        case "date":
            cell.textField?.stringValue = r.modified.map { dateFormatter.string(from: $0) } ?? ""
        case "type":
            cell.textField?.stringValue = typeName(for: r)
        default:
            cell.textField?.stringValue = r.isDir ? "" : sizeFormatter.string(fromByteCount: r.size)
        }
        return cell
    }

    func typeName(for r: Row) -> String {
        if r.isDir { return "Folder" }
        let key = r.type?.identifier ?? "?"
        if let n = typeNames[key] { return n }
        let n = r.type?.localizedDescription ?? "Document"
        typeNames[key] = n
        return n
    }

    // Type icons only: never ask for a per-file icon (that can read the file).
    func icon(for r: Row) -> NSImage {
        let type = r.isDir ? UTType.folder : (r.type ?? .data)
        if let i = icons[type.identifier] { return i }
        let i = NSWorkspace.shared.icon(for: type)
        icons[type.identifier] = i
        return i
    }
}

func makeTenK() throws -> URL {
    let dir = sandboxRoot.appendingPathComponent("spike-10k", isDirectory: true)
    let fm = FileManager.default
    if let existing = try? fm.contentsOfDirectory(atPath: dir.path), existing.count == 10_000 {
        return dir
    }
    try? fm.removeItem(at: dir)  // only ever our own sandbox folder
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    let exts = ["txt", "md", "swift", "png", "pdf", "json", "zip", "html", "csv", "sh"]
    for i in 0..<200 {
        try fm.createDirectory(at: dir.appendingPathComponent(String(format: "Folder %04d", i)),
                               withIntermediateDirectories: false)
    }
    for i in 0..<9_800 {
        let name = String(format: "file-%05d.%@", i, exts[i % exts.count])
        fm.createFile(atPath: dir.appendingPathComponent(name).path,
                      contents: Data(count: (i % 37) * 128))
    }
    return dir
}

func runList10k() throws {
    let dir = try makeTenK()
    print("folder: sandbox/spike-10k (10,000 items: 200 folders, 9,800 files)")

    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
                          styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    let scroll = NSScrollView(frame: window.contentView!.bounds)
    scroll.autoresizingMask = [.width, .height]
    scroll.hasVerticalScroller = true
    let table = NSTableView(frame: scroll.bounds)
    table.style = .fullWidth
    table.usesAlternatingRowBackgroundColors = true
    for (id, title, width) in [("name", "Name", 420.0), ("date", "Date modified", 180.0),
                               ("type", "Type", 200.0), ("size", "Size", 100.0)] {
        let c = NSTableColumn(identifier: .init(id))
        c.title = title
        c.width = width
        table.addTableColumn(c)
    }
    scroll.documentView = table
    window.contentView!.addSubview(scroll)
    let bench = BenchTable()
    table.dataSource = bench
    table.delegate = bench
    let bitmap = scroll.bitmapImageRepForCachingDisplay(in: scroll.bounds)!

    var totals: [Double] = []
    for run in 0..<6 {
        let t0 = now()
        var rows = try listFolder(dir)
        let t1 = now()
        sortRows(&rows)
        let t2 = now()
        bench.rows = rows
        table.reloadData()
        table.scrollRowToVisible(0)
        window.contentView!.layoutSubtreeIfNeeded()
        scroll.cacheDisplay(in: scroll.bounds, to: bitmap)  // draws the visible rows
        let t3 = now()
        totals.append(t3 - t0)
        print("run \(run): list \(ms(t1 - t0)), sort \(ms(t2 - t1)), table+first draw \(ms(t3 - t2)), total \(ms(t3 - t0))\(run == 0 ? "  (first run, cold caches)" : "")")
        bench.rows = []
        table.reloadData()
    }
    print("open 10k: first \(ms(totals[0])), median of next 5 \(ms(median(Array(totals.dropFirst()))))  (target < 300 ms)")

    // Scroll pass: move 120 px per frame from top to bottom and draw every frame.
    var rows = try listFolder(dir)
    sortRows(&rows)
    bench.rows = rows
    table.reloadData()
    window.contentView!.layoutSubtreeIfNeeded()
    let clip = scroll.contentView
    let maxY = table.frame.height - clip.bounds.height
    var frames: [Double] = []
    var y: CGFloat = 0
    while y <= maxY {
        let f0 = now()
        clip.scroll(to: NSPoint(x: 0, y: y))
        scroll.reflectScrolledClipView(clip)
        scroll.cacheDisplay(in: scroll.bounds, to: bitmap)
        frames.append(now() - f0)
        y += 120
    }
    let slow = frames.filter { $0 > 1.0 / 60 }.count
    print("scroll pass: \(frames.count) frames, median \(ms(median(frames))), p95 \(ms(percentile(frames, 0.95))), max \(ms(frames.max() ?? 0)), over 16.7 ms: \(slow)")

    let rss = residentMemoryMB()
    print(String(format: "memory (resident) with 10k rows loaded: %.0f MB", rss))
}

func residentMemoryMB() -> Double {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    return kr == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : -1
}

// MARK: - list-ways: which part of listing costs the time

struct StatRow {
    let name: String
    let mode: UInt16
    let size: Int64
    let mtime: Double
    let flags: UInt32
}

// readdir + fstatat: one stat per entry, no Foundation URL objects, no File Provider calls.
func listWithStat(_ path: String) -> [StatRow] {
    guard let dir = opendir(path) else { return [] }
    defer { closedir(dir) }
    let fd = dirfd(dir)
    var rows: [StatRow] = []
    while let entry = readdir(dir) {
        let name = withUnsafePointer(to: entry.pointee.d_name) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
        }
        if name == "." || name == ".." { continue }
        var st = stat()
        guard fstatat(fd, name, &st, AT_SYMLINK_NOFOLLOW) == 0 else { continue }
        rows.append(StatRow(name: name, mode: st.st_mode, size: Int64(st.st_size),
                            mtime: Double(st.st_mtimespec.tv_sec), flags: st.st_flags))
    }
    return rows
}

func runListWays() throws {
    let dir = try makeTenK()
    func time(_ label: String, _ body: () throws -> Int) rethrows {
        var t: [Double] = []
        var n = 0
        for _ in 0..<5 { let a = now(); n = try body(); t.append(now() - a) }
        print("\(label): \(n) items, median \(ms(median(t)))")
    }
    let fm = FileManager.default
    try time("contentsOfDirectory, no keys") { try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).count }
    let basic: [URLResourceKey] = [.nameKey, .isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isHiddenKey]
    try time("contentsOfDirectory + basic keys (read)") {
        let u = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: basic)
        for x in u { _ = try x.resourceValues(forKeys: Set(basic)) }
        return u.count
    }
    try time("  + contentTypeKey") {
        let k = basic + [.contentTypeKey]
        let u = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: k)
        for x in u { _ = try x.resourceValues(forKeys: Set(k)) }
        return u.count
    }
    try time("  + ubiquitous keys") {
        let k = basic + [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
        let u = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: k)
        for x in u { _ = try x.resourceValues(forKeys: Set(k)) }
        return u.count
    }
    time("readdir + fstatat") { listWithStat(dir.path).count }
    var typeCache: [String: UTType] = [:]
    time("readdir + fstatat + UTType by extension (cached)") {
        let rows = listWithStat(dir.path)
        for r in rows {
            let ext = (r.name as NSString).pathExtension.lowercased()
            if typeCache[ext] == nil { typeCache[ext] = UTType(filenameExtension: ext) ?? .data }
        }
        return rows.count
    }
    let rows = listWithStat(dir.path)
    time("sort, Swift String localizedStandardCompare") {
        let s = rows.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return s.count
    }
    let ns = rows.map { $0.name as NSString }
    time("sort, NSString localizedStandardCompare") {
        let s = ns.sorted { $0.localizedStandardCompare($1 as String) == .orderedAscending }
        return s.count
    }
    let keys = rows.map { $0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
    time("sort, precomputed folded key + numeric compare") {
        let s = keys.sorted { $0.compare($1, options: [.numeric, .literal]) == .orderedAscending }
        return s.count
    }
}

// MARK: - drive

let SF_DATALESS_FLAG: UInt32 = 0x4000_0000

func isDataless(_ path: String) -> Bool {
    var st = stat()
    return lstat(path, &st) == 0 && (st.st_flags & SF_DATALESS_FLAG) != 0
}

func runDrive(_ folder: String) throws {
    let root = URL(fileURLWithPath: (folder as NSString).expandingTildeInPath, isDirectory: true)
    let fm = FileManager.default
    // The folder and its direct subfolders, max 5,000 items. Names are never printed.
    var urls: [URL] = []
    let t0 = now()
    let top = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: listKeys, options: [])
    urls += top
    for u in top where urls.count < 5_000 {
        let v = try? u.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        if v?.isDirectory == true, v?.isPackage != true,
           let kids = try? fm.contentsOfDirectory(at: u, includingPropertiesForKeys: listKeys, options: []) {
            urls += kids.prefix(5_000 - urls.count)
        }
    }
    let t1 = now()

    var status: [String: Int] = [:]
    var ubiquitous = 0
    var datalessBefore: [String] = []
    var sizeOfDataless: Int64 = 0
    var icons: [String: NSImage] = [:]
    for u in urls {
        let v = try u.resourceValues(forKeys: Set(listKeys))
        if v.isUbiquitousItem == true { ubiquitous += 1 }
        let s = v.ubiquitousItemDownloadingStatus?.rawValue ?? "none"
        status[s, default: 0] += 1
        _ = v.contentType?.localizedDescription
        let type = (v.isDirectory ?? false) ? UTType.folder : (v.contentType ?? .data)
        if icons[type.identifier] == nil { icons[type.identifier] = NSWorkspace.shared.icon(for: type) }
        if isDataless(u.path) {
            datalessBefore.append(u.path)
            sizeOfDataless += Int64(v.fileSize ?? 0)
        }
    }
    let t2 = now()

    // Draw every type icon at 16 px, as a list would.
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 16, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    for i in icons.values { i.draw(in: NSRect(x: 0, y: 0, width: 16, height: 16)) }
    NSGraphicsContext.restoreGraphicsState()

    // Re-check with fresh URL objects: did any dataless file get materialised?
    var stillDataless = 0
    var nowDownloaded = 0
    for p in datalessBefore {
        let fresh = URL(fileURLWithPath: p)
        if isDataless(p) { stillDataless += 1 }
        let st = try? fresh.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
        if st?.ubiquitousItemDownloadingStatus == .current || st?.ubiquitousItemDownloadingStatus == .downloaded {
            nowDownloaded += 1
        }
    }
    print("items listed: \(urls.count) (folder + direct subfolders), list \(ms(t1 - t0)), read keys + type icons \(ms(t2 - t1))")
    print("isUbiquitousItem = true: \(ubiquitous); download status: \(status.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))")
    print("dataless (only in the cloud) before: \(datalessBefore.count), logical size \(ByteCountFormatter.string(fromByteCount: sizeOfDataless, countStyle: .file))")
    print("dataless after listing + icons: \(stillDataless) of \(datalessBefore.count); reported downloaded after: \(nowDownloaded)")
    print(datalessBefore.count == stillDataless ? "RESULT: no download started" : "RESULT: SOMETHING WAS DOWNLOADED")
}

// MARK: - term

@MainActor final class TermCheck: NSObject, LocalProcessTerminalViewDelegate {
    let window: NSWindow
    let term: LocalProcessTerminalView
    let start: URL
    var events: [String] = []
    var prompts = 0
    var sentCd = false
    var sawSub = false
    var oscToken: TerminalOscObservation?
    let t0 = now()

    init(start: URL) {
        self.start = start
        window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 820, height: 360),
                          styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        term = LocalProcessTerminalView(frame: window.contentView!.bounds)
        super.init()
        term.autoresizingMask = [.width, .height]
        window.contentView!.addSubview(term)
        term.processDelegate = self
        // Private OSC 6973 marks: "prompt" when the shell waits, "exec" when a command starts.
        oscToken = term.observeOscEvents { [weak self] event in
            guard event.code == 6973 else { return }
            let text = String(decoding: event.payload, as: UTF8.self)
            DispatchQueue.main.async { self?.marker(text) }
        }
    }

    func run() throws {
        let zdot = sandboxRoot.appendingPathComponent("spike-zdotdir", isDirectory: true)
        try writeShellIntegration(to: zdot)
        var env = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        env.removeAll { $0.hasPrefix("ZDOTDIR=") }
        let userZdot = ProcessInfo.processInfo.environment["ZDOTDIR"] ?? NSHomeDirectory()
        env += ["ZDOTDIR=\(zdot.path)", "LUKSFER_USER_ZDOTDIR=\(userZdot)", "TERM_PROGRAM=Luksfer",
                "HOME=\(NSHomeDirectory())", "USER=\(NSUserName())", "PATH=\(ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin")"]
        let shell = String(cString: getpwuid(getuid()).pointee.pw_shell)
        events.append("shell: \(shell) (login)")
        term.startProcess(executable: shell, args: [], environment: env,
                          execName: "-" + (shell as NSString).lastPathComponent,
                          currentDirectory: start.path)
        window.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { self.finish(timedOut: true) }
    }

    func marker(_ text: String) {
        events.append(String(format: "%.0f ms: OSC 6973 %@", (now() - t0) * 1000, text))
        if text == "prompt" {
            prompts += 1
            if !sentCd {
                sentCd = true
                term.send(txt: " cd -- 'sub dir' && printf '\\e[31mred\\e[32m green\\e[0m\\n'\r")
            } else if sawSub {
                // Resize check, then done.
                let before = term.terminalDimensions.cols
                window.setContentSize(NSSize(width: 560, height: 300))
                window.contentView!.layoutSubtreeIfNeeded()
                let after = term.terminalDimensions.cols
                events.append("resize: \(before) cols -> \(after) cols")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.finish(timedOut: false) }
            }
        }
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        let path = directory.flatMap { URL(string: $0)?.path } ?? "?"
        let rel = path.replacingOccurrences(of: start.path, with: "<start>")
        events.append(String(format: "%.0f ms: OSC 7 %@", (now() - t0) * 1000, rel))
        if path.hasSuffix("/sub dir") { sawSub = true }
    }

    func finish(timedOut: Bool) {
        let out = sandboxRoot.appendingPathComponent("spike-term.png")
        if let rep = term.bitmapImageRepForCachingDisplay(in: term.bounds) {
            term.cacheDisplay(in: term.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: out)
        }
        events.forEach { print($0) }
        print("capture: sandbox/spike-term.png")
        print(timedOut ? "RESULT: timed out" : (sawSub ? "RESULT: shell ran, prompt marks and OSC 7 after cd received" : "RESULT: no OSC 7 for cd"))
        term.terminate()
        exit(sawSub ? 0 : 1)
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func processTerminated(source: TerminalView, exitCode: Int32?) {
        events.append("shell exited: \(exitCode.map(String.init) ?? "signal")")
    }
}

// zsh integration: load the user's own startup files, then add two hooks.
func writeShellIntegration(to dir: URL) throws {
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let common = #"""
    # Luksfer shell integration (spike copy).
    __luksfer_source() {
      local f="${LUKSFER_USER_ZDOTDIR:-$HOME}/$1"
      if [[ -r "$f" ]]; then
        ZDOTDIR="${LUKSFER_USER_ZDOTDIR:-$HOME}"
        source "$f"
        LUKSFER_USER_ZDOTDIR="$ZDOTDIR"
        ZDOTDIR="$__luksfer_zdotdir"
      fi
    }
    """#
    let zshenv = #"""
    __luksfer_zdotdir="$ZDOTDIR"
    \#(common)
    __luksfer_source .zshenv
    """#
    let zprofile = "__luksfer_source .zprofile\n"
    let zshrc = #"""
    __luksfer_source .zshrc
    __luksfer_cwd() {
      local LC_ALL=C i c out=""
      for (( i = 1; i <= ${#PWD}; i++ )); do
        c="${PWD[i]}"
        if [[ "$c" == [A-Za-z0-9/._~-] ]]; then out+="$c"; else out+=$(printf '%%%02X' "'$c"); fi
      done
      printf '\e]7;file://%s%s\a' "$HOST" "$out"
    }
    __luksfer_precmd() { __luksfer_cwd; printf '\e]6973;prompt\a'; }
    __luksfer_preexec() { printf '\e]6973;exec\a'; }
    autoload -Uz add-zsh-hook
    add-zsh-hook precmd __luksfer_precmd
    add-zsh-hook preexec __luksfer_preexec
    # Hand ZDOTDIR back so .zlogin and child shells use the user's own files.
    if [[ "$LUKSFER_USER_ZDOTDIR" == "$HOME" ]]; then unset ZDOTDIR; else ZDOTDIR="$LUKSFER_USER_ZDOTDIR"; fi
    unset LUKSFER_USER_ZDOTDIR __luksfer_zdotdir
    """#
    for (name, text) in [(".zshenv", zshenv), (".zprofile", zprofile), (".zshrc", zshrc)] {
        try text.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }
}

func runTerm() throws {
    let start = sandboxRoot.appendingPathComponent("spike-term", isDirectory: true)
    try FileManager.default.createDirectory(at: start.appendingPathComponent("sub dir"),
                                            withIntermediateDirectories: true)
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    try MainActor.assumeIsolated {
        let check = TermCheck(start: start)
        try check.run()
        withExtendedLifetime(check) { app.run() }
    }
}

// MARK: - pasteboard

func runPasteboard() throws {
    let dir = sandboxRoot.appendingPathComponent("spike-pasteboard", isDirectory: true)
    let fm = FileManager.default
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    let files = ["a.txt", "b c.md"].map { dir.appendingPathComponent($0) }
    for f in files { fm.createFile(atPath: f.path, contents: Data("x".utf8)) }

    // A private, named pasteboard: the user's clipboard is never touched.
    let pb = NSPasteboard(name: .init("luksfer.spike.\(getpid())"))
    pb.clearContents()
    let cutType = NSPasteboard.PasteboardType("io.github.wawrepo.luksfer.cut")
    let ok = pb.writeObjects(files.map { $0 as NSURL })
    pb.addTypes([cutType], owner: nil)
    pb.setString("1", forType: cutType)
    let types = pb.pasteboardItems?.first?.types.map(\.rawValue) ?? []
    let back = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    let legacy = pb.propertyList(forType: .init("NSFilenamesPboardType")) as? [String]
    print("writeObjects: \(ok); item types: \(types.joined(separator: ", "))")
    print("read back as file URLs: \(back.count) of \(files.count), same paths: \(back.map(\.path) == files.map(\.path))")
    print("legacy NSFilenamesPboardType readable: \(legacy?.count ?? 0) paths")
    print("cut marker type present: \(pb.types?.contains(cutType) == true)")
    pb.releaseGlobally()
}

// MARK: - main

let args = CommandLine.arguments.dropFirst()
do {
    switch args.first {
    case "list10k": try runList10k()
    case "list-ways": try runListWays()
    case "drive":
        guard args.count >= 2 else { print("usage: LuksferSpike drive <folder>"); exit(2) }
        try runDrive(args[args.startIndex + 1])
    case "term": try runTerm()
    case "pasteboard": try runPasteboard()
    default:
        print("usage: LuksferSpike list10k | drive <folder> | term | pasteboard")
        exit(2)
    }
} catch {
    print("error: \(error)")
    exit(1)
}
