# Luksfer — PRD v0.1

Oct 30, 2026 · Waw · Status: draft

*Name: Luksfer (Polish for a glass block; the working name was Okno, Polish for "window").*

Mockup (clickable): source in `docs/mockup/`.

## 1. Problem

Finder does not work the way a long-time Windows user works, and it cannot be set to:

- The context menu has no "New file", only "New Folder".
- Enter renames a file instead of opening it.
- There is no cut and paste for files. You copy, then use ⌥⌘V to move.
- The path bar is read-only. Typing a path needs a separate dialog (⇧⌘G).
- There is one pane per window and no terminal inside the window.
- The details (list) view is not the default for every folder.

Other file managers exist (ForkLift, Path Finder, Commander One, QSpace Pro). Most follow Finder or
Total Commander habits. We have not found one built around Windows Explorer habits. The spike
checks this again before we build much.

## 2. Vision

A native macOS file explorer that works like Windows Explorer: details view first, a path you can
click or type, Favorites in the sidebar that are easy to change, and New file / New folder on every
right-click. On top of that: two panes side by side, drag and drop between them, and a terminal
inside the window. It is the app you open for everyday file work instead of Finder.

## 3. Target user

- **v1:** Waw. A developer with many years of Windows habits. Works in a Google Drive folder with
  many repos, and uses the terminal all day.
- **Later:** people who move from Windows to a Mac, and developers. Decide after the dogfood
  milestone.

## 4. Core features (v1)

1. Details view by default, in every folder.
2. One or two panes, switched with one click.
3. Path bar: click a part to jump, or type a path.
4. Favorites at the top of the sidebar: pin, reorder and unpin in one step.
5. Context menu with New folder and New text file on files, folders and empty space.
6. Drag and drop between the panes, onto folders, onto Favorites, and to and from other apps.
7. Terminal inside the app (a panel at the bottom) and outside (open a terminal app here).

## 5. Key decisions (v1)

- **Native macOS app in Swift.** The file list uses AppKit (`NSOutlineView` / `NSTableView`): it is
  fast with 10,000+ rows and has column resize, drag and drop and type-to-select built in. SwiftUI
  only where it is simpler (settings). The spike confirms this.
- **Outside the Mac App Store.** The App Store sandbox blocks a general file manager. When the app
  is shared: Developer ID signing and notarization. For v1 a local build is enough.
- **Windows keys by default:** Enter opens, F2 renames, ⌘X / ⌘C / ⌘V cut, copy and paste files,
  ⌘⌫ moves to the Trash, ⌘↑ goes up, ⌘L edits the path. A setting switches to Finder keys.
- **Delete means Trash.** A permanent delete needs ⇧ and a confirm. Every file action can be undone
  or asks first.
- **Finder stays.** macOS keeps Finder for the desktop and the Dock. Luksfer does not replace them.
- **Standard files on the clipboard and in drag and drop**, so Finder, Mail and VS Code see normal
  files.
- **Own settings only.** Favorites, columns and panes live in Luksfer's settings. Luksfer never changes
  Finder's settings or Finder's sidebar.
- **No network, no telemetry, no account.**
- **Open source later.** The repo becomes public after v1 works; no date yet. Until then it is
  private, but every commit is written as if it were public (no private data in the history).

## 6. Functional requirements

### 6.1 Window and panes

- One or two panes. A toolbar button and a shortcut switch between them.
- Each pane has its own folder, back and forward history, selection, sort and search.
- Tab moves to the other pane. The active pane has a clear mark.
- "Open in other pane", "Swap panes", and "Same folder in both".
- More windows with ⌘N. Luksfer remembers the panes and their folders between launches.

### 6.2 Details view (default)

- Columns: Name, Date modified, Type, Size. Optional: Date created, Extension. Columns can be
  resized, moved and hidden. Click a column header to sort; folders always come first.
- Details is the default for every folder. A pane can switch to Icons (with thumbnails).
- File extensions always show. Hidden files show with ⇧⌘. (the Finder key).
- Folder size stays empty, like Windows. "Calculate size" is on the context menu (later).
- Select with click, ⇧-click, ⌘-click and a drag rectangle. Type the first letters to jump to a file.
- Space opens Quick Look (the macOS preview).

### 6.3 Path bar

- Breadcrumbs: click a part to jump there. Click › after a part to list its subfolders and jump.
- Click the empty end of the bar, or press ⌘L: the bar becomes a text field with the whole path
  selected.
- It takes `~`, `/Users/...`, paths pasted from a terminal (with quotes or `\ ` escapes), relative
  paths, and file paths (the folder opens and the file is selected).
- Folders autocomplete. Tab completes, Enter goes, Esc cancels. A wrong path shows a clear message.
- Type `term`, `terminal` or `cmd` to open the terminal in this folder (the Windows `cmd` habit).
- A Copy path button, and ⌥⌘C.
- A search box per pane filters the current folder as you type. Enter searches subfolders too
  (Spotlight or our own walk; the spike decides).

### 6.4 Sidebar

- **Favorites** at the top. Pin a folder: drag it onto Favorites, or "Pin to Favorites" on its
  context menu. Reorder by drag. Unpin from the context menu or in Edit mode (↑ ↓ ✕ buttons).
  Rename the label; the path stays.
- **This Mac:** Home, Desktop, Documents, Downloads, Pictures, Google Drive.
- **Locations:** Macintosh HD, Applications, external drives (with Eject), the Trash. Network
  shares later.
- Sections fold open and closed.

### 6.5 Context menu

- **On a file:** Open, Open with ▸, Quick Look, Cut, Copy, Copy path, Rename, Duplicate, Compress,
  Move to Trash; New folder and New text file *next to this file*; Open in Terminal (inside),
  Open in Terminal app; Get Info.
- **On a folder:** Open, Open in other pane, Pin or Unpin from Favorites, Cut, Copy, Paste into,
  Copy path, Rename, Move to Trash; New folder and New text file *inside it* and *next to it*
  (in a New ▸ submenu, like Explorer); Open in Terminal (inside), Open in Terminal app.
- **On empty space:** New folder, New text file, New Markdown file, Paste, Copy path, Pin this
  folder, Open in Terminal, Open in Terminal app, Sort by, View.
- Menu items show their key shortcut.
- A new item appears with its name selected for typing, like Windows. Esc keeps the default name.
  When it is made inside a folder that no pane shows, the pane opens that folder first.

### 6.6 File actions

- Cut, copy and paste files with ⌘X, ⌘C, ⌘V. Copy and paste work both ways with Finder. A cut in
  Luksfer that is pasted in Finder becomes a copy (Finder has no cut).
- Drag and drop: between panes, onto a folder row, onto Favorites (pins it), and to and from other
  apps. Same disk: move. Other disk: copy. ⌥ forces copy, ⌘ forces move. A badge says what will
  happen.
- Name clash: Replace, Skip or Keep both, with "Do this for all" when more items follow, or Stop
  (Esc). The question shows the size and date of both items.
- After an action the status bar says what it did, with Undo where it can be undone.
- Long copies show progress in the status bar, can be stopped, and never block the window.
- Undo (⌘Z) for rename, move, copy, new item and Trash.
- Rename in place with F2.

### 6.7 Terminal

- **Inside:** a panel at the bottom of the window, like VS Code. It runs the user's login shell
  (zsh) in the folder of the active pane. ⌃` opens and closes it.
- **Follow** (on by default): `cd` in the terminal moves the active pane, and opening a folder sends
  `cd` to the terminal, but only while the shell waits at its prompt.
- **Outside:** "Open in Terminal app" opens Terminal, iTerm2, Ghostty or Warp in that folder. A
  setting picks the app.
- The `term` word in the path bar (6.3).

### 6.8 Default file viewer

- An option to make Luksfer answer "Show in Finder" and "Reveal in Finder" from other apps, where
  macOS allows it. ForkLift and Path Finder offer this; the spike checks how and on which macOS.

### 6.9 Cloud and network folders

- Google Drive folders (the macOS File Provider) list without downloading file contents. A column
  or icon shows "only in the cloud" or "on this Mac". Listing, icons and thumbnails never start a
  big download.
- Slow folders (cloud, network) load in the background. The window never freezes; the pane shows
  that it is loading.

## 7. Non-functional requirements

- **Speed:** a local folder with 10,000 items opens in under 300 ms and scrolls without dropped
  frames on Apple Silicon. The app starts in under 1 s.
- **Never block the window** on disk, network or cloud work.
- **Memory:** under 200 MB with two panes and the terminal open.
- **Safety:** delete goes to the Trash; every destructive action can be undone or asks first.
- **Privacy:** no network requests and no telemetry.
- **Native:** dark mode, the system accent color, VoiceOver labels, and every action by keyboard.
- **Platform:** Apple Silicon, macOS 15 or newer.
- **Permissions:** when macOS blocks a folder (Desktop, Documents, Downloads, external drives), Luksfer
  says why and how to allow it (Files and Folders, or Full Disk Access).

## 8. Out of scope (v1)

- Replacing the desktop or the Dock.
- Tabs inside a pane (planned right after v1).
- FTP, SFTP and cloud-storage connections; archives opened as folders; batch rename; folder compare
  and sync; a git status column; tags; a Spotlight-wide search screen.
- Windows and Linux versions; the Mac App Store.

## 9. Risks and open questions

- **macOS limits.** Finder always runs. "Show in Finder" may come to Luksfer only from apps that ask
  macOS for the file viewer. Spike.
- **The list view.** SwiftUI `Table` may be too slow or too limited for 10,000 rows and drag and
  drop; AppKit is the safer start. Spike.
- **Embedded terminal.** SwiftTerm (an AppKit terminal view that can run a local shell) is the first
  choice; check its license (MIT expected) and how it handles zsh, colors and resize. Spike.
- **Google Drive.** Reading names, sizes and icons of "online only" files must not download them.
  Test on a real Google Drive folder, read only. Spike.
- **Function keys.** F2 needs the Fn key on most Mac keyboards. Offer Enter-to-rename as a setting,
  or another rename key.
- **Name.** Trademark and domain check before any public use.
- **License** for the public repo: not chosen yet. Decide before the repo goes public.
- **Competition.** ForkLift, Path Finder, Commander One and QSpace Pro are mature. Our edge is Windows
  habits, the built-in terminal and a developer focus. It is a personal tool first.

## 10. Milestones

1. **Spike:** an AppKit details list with 10,000 rows (speed), a Google Drive folder listed without
   downloads, a SwiftTerm panel in a window, the "default file viewer" check, and drag and drop
   with Finder. A short report and the stack choice.
2. **Browser:** one pane, details view, path bar (breadcrumbs, typing, autocomplete), sidebar with
   editable Favorites, back, forward and up, Quick Look, Windows keys.
3. **File actions:** context menus with New file and New folder, rename in place, cut, copy and
   paste, Trash and Undo, the name-clash dialog, progress.
4. **Two panes and drag and drop:** between panes, onto folder rows, onto Favorites, and with other
   apps.
5. **Terminal:** the built-in panel with Follow, "Open in Terminal app", and `term` in the path bar.
6. **Dogfood:** use Luksfer as the daily file manager; set it as the default file viewer; fix what
   hurts. Then decide on tabs, the icons view, the license, and when the repo goes public.
