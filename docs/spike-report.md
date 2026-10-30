# Spike report (milestone 1)

Oct 30, 2026 · Mac: Apple Silicon, macOS 26, Xcode 27, Swift 6.4

The spike code is in `Spike/main.swift`. Run it with
`scripts/build.sh -c release --product OknoSpike`, then
`~/Library/Caches/okno-dev/build/okno/release/OknoSpike <check>`. Every write goes to
`~/Library/Caches/okno-dev/sandbox/`.

## Result

Every risky part works on this Mac. Okno is built with **Swift and AppKit**, with **SwiftTerm**
for the terminal. One finding changes the design: the app lists folders with `readdir` + `fstatat`,
not with Foundation's URL resource keys, because the cloud-status keys are 33 times slower.

## 1. List speed: 10,000 items

A sandbox folder with 200 folders and 9,800 files. "Open" means: list, sort (folders first,
Finder order), fill a view-based `NSTableView` with 4 columns, and draw the first screen.

| Way to list | 10,000 items (median of 5) |
|---|---|
| `contentsOfDirectory`, no keys | 20.5 ms |
| + name, folder, size, date, hidden keys | 44.3 ms |
| + `contentTypeKey` | 87.3 ms |
| + cloud keys (`isUbiquitousItem`, `ubiquitousItemDownloadingStatus`) | **725.4 ms** |
| `readdir` + `fstatat`, type from the file extension (cached) | **22.1 ms** |

| Whole open (fast listing) | Time |
|---|---|
| First open | 142.7 ms |
| Median of the next 5 | 113.7 ms (list 24 ms, sort 51 ms, table and first draw 38 ms) |
| Target (PRD §7) | under 300 ms |

- Sorting with `NSString.localizedStandardCompare` is 28 ms; the same call on Swift `String` is
  47 ms because of bridging. The app keeps names as `NSString` for sorting.
- Scrolling, measured offscreen: 1,995 frames of 120 px, every frame fully redrawn. Median 11.4 ms,
  95th percentile 20.2 ms. This is a worst case: on screen, AppKit reuses the layers it already
  drew. Scroll smoothness on screen is checked by hand in the app.
- Memory of the spike process with 10,000 rows loaded: 179 MB (includes offscreen bitmaps).
- SwiftUI `Table` was not tried: AppKit meets the target with a wide margin, and AppKit has the
  drag and drop, type-to-select and column features the PRD needs.

## 2. Google Drive: listing without downloads

Read only. The folder and its direct subfolders were listed with the keys the app needs, every type
icon was drawn, and then each "only in the cloud" file was checked again.

| Folder | Items | Only in the cloud | After listing and icons |
|---|---|---|---|
| Google Drive in `~/Library/CloudStorage/` (File Provider) | a few hundred | most | all still only in the cloud |
| A local synced folder (not File Provider) | a few hundred | 0 | — |

- **No download started.**
- "Only in the cloud" = the `SF_DATALESS` flag in `st_flags` (from `fstatat`). It matched the
  File Provider status exactly (every file it marked was "not downloaded"). It costs nothing extra, so the
  cloud-status keys are never needed for the list.
- Rules for the app: icons come from the file type (`NSWorkspace.icon(for: UTType)`), never from the
  file (`icon(forFile:)` can read it). No thumbnails in cloud folders. Folder size stays empty.
  Copying a cloud-only file downloads it; that is the user's own action.
- Listing a File Provider folder with the cloud keys took about 1 s for a few hundred items. The fast listing
  avoids that cost. Slow folders still load in the background.

## 3. Terminal: SwiftTerm

- SwiftTerm 1.99.2 (Swift Package), **MIT license**. `LocalProcessTerminalView` runs a process in a
  pseudo-terminal (a fake keyboard-and-screen device the shell talks to).
- The login shell (`/bin/zsh`, started as `-zsh`) ran with the user's own startup files, prompt
  theme and colors. Resize works (102 to 70 columns).
- **Folder tracking works.** Okno points `ZDOTDIR` at its own small startup files. They load the
  user's files first, then add two hooks:
  - OSC 7 (an escape code that reports the shell's folder) after every command.
  - A private OSC 6973 mark: `prompt` when the shell waits, `exec` when a command starts.
- Timeline: first prompt after about 1.5 s (the user's own startup files); `cd` reported the new folder 41 ms after
  it was sent.
- Found: the `precmd` hook runs *before* the prompt is drawn, so text sent there shows twice. The
  app sends the `prompt` mark from the line editor's `line-init` hook instead, and sends `cd` only
  when nothing has been typed since.
- Some user configs send their own OSC 7 too; the app ignores repeats of the same folder.

## 4. Drag and drop and the clipboard with Finder

- Files go on the pasteboard as `NSURL` objects (`public.file-url`), one item per file. Read back
  from a private pasteboard: 2 of 2 paths, and the old `NSFilenamesPboardType` that older apps
  read also works. This is the format Finder writes and reads.
- A cut is a normal file copy plus a private marker type (`app.okno.cut`). Okno moves on paste when
  the marker is there. Finder ignores the marker, so a cut pasted in Finder becomes a copy (PRD §6.6).
- Drag and drop uses the same pasteboard data. A real drag between Okno and Finder can only be done
  by hand; it is checked in milestone 4.

## 5. Default file viewer ("Show in Finder")

- ForkLift and Path Finder use the global `NSFileViewer` default (the bundle id of the file
  viewer). AppKit's `NSWorkspace` "reveal" calls (`activateFileViewerSelecting`,
  `selectFile(_:inFileViewerRootedAtPath:)`) send the request to that app instead of Finder.
- Apps that tell Finder directly (AppleScript, `open -R` on some versions) still go to Finder. So
  "Show in Finder" reaches Okno only from apps that ask macOS for the file viewer, as the PRD expects.
- Not set on this Mac (`NSFileViewer` does not exist). The spike did not change it: it is a global
  setting, and changing it is the user's choice in milestone 6. That milestone adds an opt-in
  switch and tests the exact request Okno receives.

## Stack choice

| Part | Choice |
|---|---|
| Language | Swift 6.4 toolchain, Swift 5 language mode (simpler AppKit code; move to 6 later) |
| UI | AppKit. View-based `NSTableView` for the file list. SwiftUI only for Settings. |
| Listing | `readdir` + `fstatat` on a background queue; type from the extension (cached `UTType`); cloud status from `SF_DATALESS`; type icons only |
| Terminal | SwiftTerm `LocalProcessTerminalView`; zsh integration through `ZDOTDIR` (OSC 7 + OSC 6973) |
| Project | Swift Package (no Xcode project): `OknoCore` (logic, unit tests), `Okno` (app), `OknoSpike` |
| App bundle | `scripts/build-app.sh` builds `Okno.app` in `~/Library/Caches/okno-dev/dist/` |
| Builds | `scripts/build.sh` (through `scripts/heavy.sh`: one heavy job at a time, `-j 6`), output in `~/Library/Caches/okno-dev/build/` |
| Settings | JSON in `~/Library/Application Support/Okno/` |
