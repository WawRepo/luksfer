<h1 align="center"><img src="docs/brand/logo.png" alt="Luksfer" width="380"></h1>

Luksfer is a native macOS file explorer that works like Windows Explorer. "Luksfer" is Polish
for a glass block, the brick that lets light through a wall.

I used Windows for three decades and finally moved to a Mac. Everything was fine except Finder.
Enter renames a file instead of opening it, and right-click won't even make a new one. Explorer
arrived with Windows 95 in 1995, so that's thirty years of habits burned in, and they're not
going anywhere.

So Claude came to the rescue. I explained how Explorer works, Claude wrote the code, and now I
have my Explorer back.

I just needed something simple, without feature overload. If you need something more, feel free
to fork it or [open an issue](../../issues).

**Status:** early (version 0.1). The main features work; expect rough edges.

![Luksfer with two panes: a Projects folder on the left and Downloads on the right](docs/images/two-panes.png)

## What it does

- Details view by default, in every folder: Name, Date modified, Type, Size.
- One or two panes, with drag and drop between them.
- A path bar you can click or type into, with folder autocomplete. Type `term` to open a terminal.
- A search box that filters the folder as you type. Enter also searches the subfolders.
- Favorites in the sidebar: drag a folder in to pin it, drag to reorder, right-click to unpin.
- New folder and New text file on every right-click. Compress and Extract for zip files.
- Windows keys: Enter opens, F2 renames, ⌘X / ⌘C / ⌘V cut, copy and paste files. The back and
  forward buttons of a mouse work too.
- Delete moves to the Trash. Every file action can be undone, or asks first.
- A terminal panel at the bottom of the window that follows the folder you are in, and
  "Open in Terminal App" for Terminal, iTerm2, Ghostty or Warp.
- Network drives (SMB), like Explorer's "Map network drive". Passwords stay in the macOS Keychain.
- A new window from any app with ⌥⌘Space, like Win+E (see below).

![Luksfer with the terminal panel open below the file list](docs/images/terminal.png)

## A new window from any app

Press ⌥⌘Space in any app, Luksfer included, to open a new single-pane window in Downloads, like
Win+E on Windows.

- Luksfer has to run for the key to work. It keeps running when you close its last window. To
  start it when you log in, turn on Settings > "Open Luksfer at login".
- macOS uses ⌥⌘Space for the Finder search window. Turn that off first: System Settings > Keyboard >
  Keyboard Shortcuts… > Spotlight > "Show Finder search window".
- To turn the key off, use Settings > "⌥⌘Space opens a new window in Downloads". Luksfer then quits
  when you close its last window.

## Install

1. Download `Luksfer-<version>.dmg` from the [Releases page](../../releases).
2. Open it and drag Luksfer to Applications.
3. Open Luksfer. The app is not notarized by Apple, so macOS blocks the first open and shows
   "Luksfer" Not Opened. Click **Done**, not **Move to Trash**.
4. Quit System Settings if it is open, then open it again. Go to Privacy & Security and scroll down
   to Security.
5. Click **Open Anyway** under "Allow applications from" and confirm with your password or Touch ID.
   You do this only once per version.

If **Open Anyway** does not appear, run this line. It removes the quarantine flag (the mark that
makes macOS block a downloaded app) from Luksfer only, then opens the app. Run it only on a copy you
trust; the check below shows that GitHub built your copy.

```sh
xattr -dr com.apple.quarantine /Applications/Luksfer.app && open /Applications/Luksfer.app
```

If you replace an older version that you keep in the Dock, Finder moves the old copy to the Trash
and the Dock icon can still point to it. Remove that icon from the Dock, open the new app, then
right-click its icon and choose Options > Keep in Dock.

To check that GitHub built your copy from this repo, use the [GitHub CLI](https://cli.github.com):

```sh
gh attestation verify Luksfer-<version>.dmg --repo WawRepo/luksfer
```

Needs a Mac with Apple Silicon and macOS 15 or newer.

## Privacy

- No network requests, no telemetry, no account. The one exception is a network drive that you set
  up: macOS makes that connection.
- Listing a cloud folder (Google Drive and other File Provider folders) never downloads a file.
  Luksfer reads names, sizes and dates only, and draws icons from the file type.
- Luksfer keeps its own settings in `~/Library/Application Support/Luksfer/`. It never changes
  Finder's settings or Finder's sidebar. Network drive passwords go to the macOS Keychain, never
  into the settings file.

## Build from source

You need Xcode with the Swift 6.4 toolchain (Xcode's `actool` also builds the app icon). The
scripts build outside the repo, in `~/Library/Caches/luksfer-dev/`, so a checkout in a synced
folder stays clean.

```sh
scripts/build-app.sh                  # writes ~/Library/Caches/luksfer-dev/dist/Luksfer.app
open ~/Library/Caches/luksfer-dev/dist/Luksfer.app

scripts/build.sh                      # debug build of the package
LUKSFER_SWIFT=test scripts/build.sh   # unit tests (LuksferCoreTests)
scripts/release.sh v0.1.0             # ~/Library/Caches/luksfer-dev/release/Luksfer-0.1.0.dmg
```

To publish a release, push a version tag (`git tag v0.1.0 && git push origin v0.1.0`). The
[release workflow](.github/workflows/release.yml) builds the disk image and attaches it to a GitHub
Release.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md): the rules every change follows, and the in-app self-test.
The product requirements are in [docs/PRD.md](docs/PRD.md).

## Project layout

```text
Package.swift             Swift package, no Xcode project
Sources/LuksferCore/      file system logic, no UI: listing, file operations and undo, paths,
                          navigation, network drives, settings, shell integration
Sources/Luksfer/          the AppKit app: window, panes, file list, path bar, sidebar, menus,
                          terminal panel, network drive dialogs
Tests/LuksferCoreTests/   unit tests for LuksferCore
Spike/                    the speed and feasibility checks that chose the stack
Resources/                app icon, built by scripts/make-icon.py
scripts/                  build, test, release and icon scripts
docs/PRD.md               product requirements
docs/spike-report.md      spike results and the stack choice
docs/brand/               the icon and logo source image, and the logo
.github/workflows/        CI (tests on every push) and the release build
```

## License

MIT. See [LICENSE](LICENSE).

Third-party code and its licenses: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
