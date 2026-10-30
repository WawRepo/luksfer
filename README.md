# Okno

Okno is a native macOS file explorer that works like Windows Explorer. "Okno" is Polish for
"window", and it is a working name.

**Status:** early. Version 1 is built for one user, the author, as a daily file manager. It is not
signed for distribution and there are no releases yet.

## What it does

- Details view by default, in every folder: Name, Date modified, Type, Size.
- One or two panes, with drag and drop between them.
- A path bar you can click or type into, with folder autocomplete. Type `term` to open a terminal.
- Favorites in the sidebar: drag a folder in to pin it, drag to reorder, right-click to unpin.
- New folder and New text file on every right-click.
- Windows keys: Enter opens, F2 renames, ⌘X / ⌘C / ⌘V cut, copy and paste files.
- Delete moves to the Trash. Every file action can be undone, or asks first.
- A terminal panel at the bottom of the window that follows the folder you are in, and
  "Open in Terminal app" for Terminal, iTerm2, Ghostty or Warp.

## Privacy

- No network requests, no telemetry, no account.
- Listing a cloud folder (Google Drive and other File Provider folders) never downloads a file.
  Okno reads names, sizes and dates only, and draws icons from the file type.
- Okno keeps its own settings in `~/Library/Application Support/Okno/`. It never changes
  Finder's settings or Finder's sidebar.

## Requirements

- A Mac with Apple Silicon, macOS 15 or newer.
- Xcode with the Swift 6.4 toolchain. `scripts/build-app.sh` also uses Xcode's `actool` for the
  app icon.

## Build and run

The scripts build outside the repo, in `~/Library/Caches/okno-dev/`, and run one heavy job
(build, tests) at a time.

```sh
scripts/build-app.sh                  # writes ~/Library/Caches/okno-dev/dist/Okno.app
open ~/Library/Caches/okno-dev/dist/Okno.app

scripts/build.sh                      # debug build of the package
OKNO_SWIFT=test scripts/build.sh      # unit tests (OknoCoreTests)
```

The app also has an in-app self-test that drives the real window (file actions, keys, drag and
drop, terminal Follow). It is described in [CLAUDE.md](CLAUDE.md), under "In-app self-test". Give it
sandbox folders, never your real ones.

## Project layout

```text
Package.swift            Swift package, no Xcode project
Sources/OknoCore/        file system logic, no UI: listing, file operations and undo, paths,
                         navigation, settings, shell integration
Sources/Okno/            the AppKit app: window, panes, file list, path bar, sidebar, menus,
                         terminal panel
Tests/OknoCoreTests/     unit tests for OknoCore
Spike/                   the speed and feasibility checks that chose the stack
Resources/               app icon
scripts/                 build, test and icon scripts
docs/PRD.md              product requirements
docs/spike-report.md     spike results and the stack choice
docs/mockup/             source of the clickable mockup
```

## License

Not chosen yet. Until a license is added, no rights are granted to use, copy or change this code.

Third-party code and its licenses: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
