<h1 align="center"><img src="docs/brand/logo.png" alt="Luksfer" width="380"></h1>

Luksfer is a native macOS file explorer that works like Windows Explorer. "Luksfer" is Polish
for a glass block, the brick that lets light through a wall. Its working name was Okno (Polish
for "window"), so older commits use that name.

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
  Luksfer reads names, sizes and dates only, and draws icons from the file type.
- Luksfer keeps its own settings in `~/Library/Application Support/Luksfer/`. It never changes
  Finder's settings or Finder's sidebar.

## Requirements

- A Mac with Apple Silicon, macOS 15 or newer.
- Xcode with the Swift 6.4 toolchain. `scripts/build-app.sh` also uses Xcode's `actool` for the
  app icon.

## Build and run

The scripts build outside the repo, in `~/Library/Caches/luksfer-dev/`, and run one heavy job
(build, tests) at a time.

```sh
scripts/build-app.sh                  # writes ~/Library/Caches/luksfer-dev/dist/Luksfer.app
open ~/Library/Caches/luksfer-dev/dist/Luksfer.app

scripts/build.sh                      # debug build of the package
LUKSFER_SWIFT=test scripts/build.sh      # unit tests (LuksferCoreTests)
```

The app also has an in-app self-test that drives the real window (file actions, keys, drag and
drop, terminal Follow). It is described in [CLAUDE.md](CLAUDE.md), under "In-app self-test". Give it
sandbox folders, never your real ones.

## Project layout

```text
Package.swift             Swift package, no Xcode project
Sources/LuksferCore/      file system logic, no UI: listing, file operations and undo, paths,
                          navigation, settings, shell integration
Sources/Luksfer/          the AppKit app: window, panes, file list, path bar, sidebar, menus,
                          terminal panel
Tests/LuksferCoreTests/   unit tests for LuksferCore
Spike/                    the speed and feasibility checks that chose the stack
Resources/                app icon, built by scripts/make-icon.py
scripts/                  build, test and icon scripts
docs/PRD.md               product requirements
docs/spike-report.md      spike results and the stack choice
docs/mockup/              source of the clickable mockup
docs/brand/               the icon and logo source image, and the logo
```

## License

MIT. See [LICENSE](LICENSE).

Third-party code and its licenses: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
