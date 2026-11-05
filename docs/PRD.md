# Luksfer — Product requirements

Version 0.2 · October 2026 · Status: milestones 1–5 are built; milestone 6 (daily use) is next.

Luksfer is a native macOS file explorer that works like Windows Explorer. "Luksfer" is Polish for a
glass block, the brick that lets light through a wall.

Items marked *(planned)* are not built yet. Everything else is in the app today.

## 1. Problem

Finder does not work the way a long-time Windows user works, and it cannot be set to:

- The context menu has no "New file", only "New Folder".
- Enter renames a file instead of opening it.
- There is no cut and paste for files. You copy, then press ⌥⌘V to move.
- The path bar is read-only. To type a path you open a separate dialog (⇧⌘G).
- There is one pane per window, and no terminal inside the window.
- The details (list) view is not the default for every folder.

Other file managers exist (ForkLift, Path Finder, Commander One, QSpace Pro). Most follow Finder or
Total Commander habits. None is built around Windows Explorer habits.

## 2. Vision

A native macOS file explorer that works like Windows Explorer: details view first, a path you can
click or type, Favorites in the sidebar that are easy to change, and New file / New folder on every
right-click. On top of that: two panes side by side, drag and drop between them, and a terminal
inside the window. It is the app you open for everyday file work instead of Finder.

## 3. Who it is for

- **Version 1:** the author, a developer with many years of Windows habits who works in a
  cloud-synced folder full of repos and uses the terminal all day.
- **Later:** people who move from Windows to a Mac, and developers in general. This is decided after
  milestone 6.

## 4. Principles

- **Native macOS app in Swift.** The file list is an AppKit `NSTableView`: it is fast with 10,000+
  rows and has column resize, drag and drop and type-to-select built in. SwiftUI only where it is
  simpler (Settings). The spike chose this stack (`docs/spike-report.md`).
- **Windows keys by default:** Enter opens, F2 renames, ⌘X / ⌘C / ⌘V cut, copy and paste files,
  ⌘⌫ moves to the Trash, ⌘↑ goes up, ⌘L edits the path. A setting switches to Finder keys.
- **Never lose a file.** Delete moves to the Trash. A permanent delete asks first. Every file action
  can be undone, or asks first.
- **Finder stays.** macOS keeps Finder for the desktop and the Dock. Luksfer does not replace them.
- **Standard files on the clipboard and in drag and drop**, so Finder, Mail and VS Code see normal
  files.
- **Own settings only.** Favorites, columns and panes live in Luksfer's settings
  (`~/Library/Application Support/Luksfer/`). Luksfer never changes Finder's settings or Finder's
  sidebar.
- **No network, no telemetry, no account.** The one exception is a network drive that the user sets
  up; macOS makes that connection.
- **Open source** under the MIT license. Distributed outside the Mac App Store, because the App Store
  sandbox blocks a general file manager.

## 5. Features

### 5.1 Window and panes

- One or two panes. A toolbar button, ⌥⌘1 and ⌥⌘2 switch between them.
- Each pane has its own folder, back and forward history, selection, sort and search.
- Tab moves to the other pane. The active pane has a clear mark.
- Open in Other Pane, Swap Panes (⌥⌘U) and Same Folder in Both (⌥⌘=).
- Back and forward: the toolbar buttons, ⌘[ and ⌘], Backspace, and the back and forward buttons of a
  mouse. The mouse buttons work on the pane under the pointer, like Explorer.
- More windows with ⌘N. Luksfer remembers its windows, panes and folders between launches.
- A new window without a saved state is one pane in Downloads.
- ⌥⌘Space opens a new single-pane window in Downloads from any app, Luksfer included, like Win+E.
  It is a global hot key that needs no permission. While it is on (Settings, on by default),
  Luksfer keeps running after its last window closes. Settings can also open Luksfer at login; a
  launch at login opens no window. Each new window sits a little down and right of the front one.
- A request to open a folder (`open -a Luksfer <folder>`, a folder dropped on the Dock icon) gets
  its own single-pane window. When Luksfer comes to the front with no window on screen (⌘Tab, the
  Dock), its minimized windows come back.

### 5.2 Details view

- Columns: Name, Date modified, Type and Size. Date created and Extension can be turned on. Columns
  can be resized, moved and hidden.
- Click a column header to sort. Like Explorer, folders come first in an ascending sort and last in
  a descending one.
- Details is the default for every folder. *(planned)* A pane can switch to Icons, with thumbnails.
- File extensions always show. Hidden files are off by default; ⇧⌘. (the Finder key) shows them, and
  Luksfer remembers the choice.
- A folder's size stays empty, like Explorer. *(planned)* "Calculate size" on the context menu.
- Select with click, ⇧-click, ⌘-click and a drag rectangle. Type the first letters to jump to a file.
- Space opens Quick Look (the macOS preview).

### 5.3 Path bar and search

- Breadcrumbs: click a part to jump there. Click › after a part to list its subfolders.
- Click the empty end of the bar, or press ⌘L: the bar becomes a text field with the whole path
  selected.
- It takes `~`, absolute paths, paths pasted from a terminal (with quotes or `\ ` escapes), relative
  paths, and file paths (the folder opens and the file is selected).
- Folders autocomplete. Tab completes, Enter goes, Esc cancels. A wrong path shows a clear message.
- Type `term`, `terminal` or `cmd` to open the terminal in this folder (the Windows `cmd` habit).
- Copy Path: a button, ⌥⌘C, and the context menu.
- A search box per pane (⌘F) filters the current folder as you type. Enter also searches the
  subfolders. Results come in as Luksfer finds them, with a Folder column that says where each one
  is, and every file action works on them. Stop ends the search and keeps the results. Esc, Back or
  new text returns to the folder. "Open Containing Folder" on the context menu goes to the result's
  folder.
- The search matches names only. It does not follow links, open packages (`.app`) or enter another
  disk or network drive inside the folder. It stops at 20,000 results. It never opens a folder whose
  list is only in the cloud, and the status bar counts the folders it did not search.

### 5.4 Sidebar

- **Favorites** at the top. Pin a folder: drag it onto Favorites, or use "Pin to Favorites". Drag to
  reorder. Unpin from the context menu or in Edit mode (↑ ↓ ✕ buttons). Rename a label; the path
  stays.
- **This Mac:** Home, Desktop, Documents, Downloads, Pictures, and cloud folders such as Google
  Drive.
- **Locations:** the start disk, Applications, external drives (with Eject), the Trash.
- **Network:** saved network drives (5.8), then network volumes that were mounted some other way.
- Sections fold open and closed.

### 5.5 Context menus

- **On a file:** Open, Open With ▸, Quick Look, Cut, Copy, Copy Path, Rename, Duplicate, Compress,
  Extract (zip, 7z and tar files), Move to Trash; New folder and New text file *next to this file*; Open in Terminal (inside), Open in
  Terminal App; Get Info.
- **On a folder:** Open, Open in Other Pane, Pin to or Unpin from Favorites, Cut, Copy, Paste Into
  Folder, Copy Path, Rename, Move to Trash; a New ▸ submenu with a folder or text file *inside it* or
  *next to it*; Open in Terminal (inside), Open in Terminal App.
- **On empty space:** New Folder, New Text File, New Markdown File, Paste, Copy Path, Pin This Folder,
  Open in Terminal, Open in Terminal App, Sort By, View.
- Menu items show their key shortcuts.
- A new item appears with its name selected for typing, like Explorer. Esc keeps the default name.
  When it is made inside a folder that no pane shows, the pane opens that folder first.

### 5.6 File actions

- Cut, copy and paste files with ⌘X, ⌘C and ⌘V. Copy and paste work both ways with Finder. A cut in
  Luksfer that is pasted in Finder becomes a copy (Finder has no cut).
- Drag and drop: between panes, onto a folder row, onto Favorites (this pins the folder), and to and
  from other apps. Same disk: move. Other disk: copy. ⌥ forces a copy, ⌘ forces a move. A badge
  shows what will happen.
- Name clash: Replace, Skip or Keep Both, with "Do this for all" when more items follow, or Stop
  (Esc). The question shows the size and date of both items.
- After an action, the status bar says what it did, with Undo where it can be undone.
- Long copies show progress in the status bar, can be stopped, and never block the window.
- Undo (⌘Z) for rename, move, copy, new item and Trash. One Undo undoes one action.
- Extract puts what is in an archive next to it, and the archive stays. It knows `.zip`, `.7z`,
  `.tar`, `.tar.gz`, `.tgz`, `.tar.bz2`, `.tbz2`, `.tar.xz` and `.txz`, with the tools in macOS
  (`ditto` for zip, `tar` for the rest). One item at the top of the archive comes out as itself;
  several come out in a folder named after the archive. A taken name gets a number, so nothing is
  overwritten. A failed extract leaves nothing behind. Undo moves the result to the Trash. A
  downloaded archive's quarantine mark carries over, so macOS still checks what comes out. An
  archive with a password shows an error. RAR and a lone `.gz` file get no Extract.
- Rename in place with F2 (or Enter with Finder keys).

### 5.7 Terminal

- **Inside:** a panel at the bottom of the window, like VS Code. It runs the user's login shell
  (zsh) in the folder of the active pane. ⌃` opens and closes it.
- **Follow** (on by default): `cd` in the terminal moves the active pane, and opening a folder moves
  the shell, but only while the shell waits at its prompt.
- **Outside:** Open in Terminal App (⌥⌘T) opens Terminal, iTerm2, Ghostty or Warp in that folder. A
  setting picks the app.
- The `term` word in the path bar (5.3).
- Text a program prints cannot read or set the clipboard (OSC 52 is off, like Terminal.app). ⌘C and
  ⌘V work as usual. It also cannot pass as a report from the shell: each zsh gets a random key that
  child programs never see, and Luksfer reads only reports with that key.

### 5.8 Network drives

- Add a drive like Explorer's "Map network drive": the + on the Network section, or ⌘K. The dialog
  asks for the address (`smb://server/share` or `\\server\share`), a name, the user name (empty for a
  guest) and the password.
- Click a drive to connect. It opens in the active pane. A connected drive shows Disconnect (the
  Eject button). The context menu has Connect or Open, Open in Other Pane, Disconnect, Edit and
  Remove from Sidebar.
- The password goes to the macOS Keychain only, never into the settings file. Luksfer never shows a
  saved password again; Edit can only replace it. Without a saved password, Connect asks for it.
- macOS makes the connection (NetFS). It runs in the background and the Stop button ends it.
- Only SMB for now.

### 5.9 Cloud folders and slow volumes

- Cloud folders (Google Drive and other macOS File Provider folders) list without downloading file
  contents. An icon shows "only in the cloud". Listing, searching, sizes and icons never start a
  download.
- Slow folders (cloud, network) load in the background. The window never freezes; the pane shows that
  it is loading, and the old rows go away so nothing acts on the old folder.
- A network server that goes away never freezes the sidebar: Luksfer reads the mount table without
  waiting for a server.

### 5.10 Settings

- Keys: Windows (Enter opens, F2 renames) or Finder (Enter renames, ⌘↓ opens).
- Show hidden files.
- The terminal app for Open in Terminal App, and Follow on or off.

### 5.11 Default file viewer *(planned)*

- An opt-in switch that makes Luksfer answer "Show in Finder" and "Reveal in Finder" from other apps,
  where macOS allows it. The spike found that this reaches Luksfer only from apps that ask macOS for
  the file viewer (`NSFileViewer`), the same limit that ForkLift and Path Finder have.

## 6. Quality requirements

- **Speed:** a local folder with 10,000 items opens in under 300 ms and scrolls without dropped
  frames on Apple Silicon. The app starts in under 1 s.
- **Never block the window** on disk, network or cloud work.
- **Memory:** under 200 MB with two panes and the terminal open.
- **Safety:** delete goes to the Trash; every destructive action can be undone or asks first.
- **Privacy:** no network requests and no telemetry, except a network drive that the user set up.
- **Native:** dark mode, the system accent color, VoiceOver labels, and every action by keyboard.
- **Permissions:** when macOS blocks a folder (Desktop, Documents, Downloads, external drives),
  Luksfer says why and how to allow it (Files and Folders, or Full Disk Access).
- **Platform:** Apple Silicon, macOS 15 or newer.

## 7. Distribution

- Each version is a GitHub Release with a disk image (`Luksfer-<version>.dmg`), its SHA-256
  checksum and an attestation: a signed record of the repo, commit and workflow that built the
  file. A GitHub Actions workflow builds it when a version tag (`v0.1.0`) is pushed.
- Anyone can check a copy with `gh attestation verify Luksfer-<version>.dmg --repo WawRepo/luksfer`.
- Install: open the disk image and drag Luksfer to Applications.
- The app is not notarized in version 1, so macOS blocks the first open. The user allows it once
  in System Settings > Privacy & Security > Open Anyway. `scripts/release.sh` can sign with
  Developer ID and notarize if this changes.

## 8. Out of scope for version 1

- Replacing the desktop or the Dock.
- Tabs inside a pane: two panes and new windows are enough.
- A preview pane: Space already opens Quick Look.
- Batch rename: an agent or a script in the terminal can do it.
- FTP, SFTP, AFP, NFS and cloud-storage connections; archives opened as folders; folder compare and
  sync; a git status column; tags; a Spotlight-wide search screen.
- Windows and Linux versions; the Mac App Store.

## 9. Risks and open questions

- **"Show in Finder".** Finder always runs, and other apps reach Luksfer only when they ask macOS for
  the file viewer (5.11).
- **Function keys.** F2 needs the Fn key on most Mac keyboards. The Finder keys setting makes Enter
  rename instead.
- **Competition.** ForkLift, Path Finder, Commander One and QSpace Pro are mature. Luksfer's edge is
  Windows habits, the built-in terminal and a developer focus.

## 10. Milestones

1. **Spike** — done. An AppKit details list with 10,000 rows, a Google Drive folder listed without
   downloads, a SwiftTerm panel, the "default file viewer" check, and drag and drop with Finder.
   Results: `docs/spike-report.md`.
2. **Browser** — done. One pane, details view, path bar (breadcrumbs, typing, autocomplete), sidebar
   with editable Favorites, back, forward and up, Quick Look, Windows keys.
3. **File actions** — done. Context menus with New file and New folder, rename in place, cut, copy
   and paste, Trash and Undo, the name-clash dialog, progress.
4. **Two panes and drag and drop** — done. Between panes, onto folder rows, onto Favorites, and with
   other apps.
5. **Terminal** — done. The built-in panel with Follow, Open in Terminal App, and `term` in the path
   bar. Network drives were added after this milestone.
6. **Daily use** — next. Use Luksfer as the everyday file manager, fix what hurts, add the default
   file viewer switch. Then decide on the Icons view.
7. **First public release** — a disk image on GitHub Releases, with an attestation and clear
   install steps.
