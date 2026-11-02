# Contributing to Luksfer

Thank you for helping. Read [docs/PRD.md](docs/PRD.md) first: it says what Luksfer does and what
it does not do. The PRD is the source of truth; change it in the same pull request when a feature
changes.

## Rules every change follows

- **Never lose a user's file.** Delete moves to the Trash. Every destructive action (overwrite,
  move over a name clash, permanent delete) can be undone or asks first.
- **Tests write only inside their own sandbox folder** under `~/Library/Caches/luksfer-dev/`, which
  the test makes itself. A test never creates, moves, renames or deletes anything in real folders
  (`~/Documents`, `~/Downloads`, `~/Desktop`, cloud folders). Reading a real folder to measure speed
  is fine. A test that writes outside its sandbox is a bug.
- **Listing must not download.** Listing a Google Drive or other cloud folder, reading sizes or
  drawing icons must never start a download. Never read the cloud-status URL resource keys in the
  file list, and never ask for a per-file icon.
- **No network, no telemetry, no account.** The one exception: a network drive the user set up.
  macOS makes that connection (NetFS); Luksfer only hands it the address, user and password.
- **Own settings only.** Luksfer writes its settings to `~/Library/Application Support/Luksfer/`
  and never changes Finder's settings or Finder's sidebar. Network drive passwords go to the macOS
  Keychain, never into the settings file, and the app never shows them again.
- **No private data** in code, commits, docs, test data or screenshots: no secrets, host names, IP
  addresses (use the documentation ranges, such as `192.0.2.x`) or real people's file names. Use
  made-up names.

## Stack

- Swift package, no Xcode project. Swift 6.4 toolchain in Swift 5 language mode. macOS 15 or newer,
  Apple Silicon.
- `LuksferCore`: file system logic with no UI, unit tests in `Tests/LuksferCoreTests`.
  `Luksfer`: the AppKit app. `LuksferSpike`: the checks that chose the stack
  ([docs/spike-report.md](docs/spike-report.md)).
- AppKit; the file list is a view-based `NSTableView`. SwiftUI only for Settings.
- Listing: `readdir` + `fstatat` on a background queue; the type comes from the file extension, and
  "only in the cloud" from the `SF_DATALESS` flag.
- Terminal: [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) (MIT). zsh integration through
  `ZDOTDIR`: a private OSC 6973 with a per-shell key reports the folder, the prompt and each command.

## Build and test

```sh
scripts/build.sh                      # debug build
LUKSFER_SWIFT=test scripts/build.sh   # unit tests
scripts/build-app.sh                  # ~/Library/Caches/luksfer-dev/dist/Luksfer.app
scripts/readme-shots.sh               # the README screenshots, with made-up files in a sandbox
```

Build output goes to `~/Library/Caches/luksfer-dev/`, never into the repo. The scripts run one
heavy job (build or test run) at a time through `scripts/heavy.sh`.

## In-app self-test

`LUKSFER_SELFTEST=1` drives the real app (file actions, keys, mouse buttons, drag and drop, terminal
Follow, network drive setup) and prints `selftest: PASS` and `selftest: FAIL` lines, then quits with
exit code 1 on a failure. Always give it sandbox folders:

```sh
root=~/Library/Caches/luksfer-dev/sandbox/selftest
rm -rf "$root"; mkdir -p "$root/folder" "$root/trash" "$root/settings" "$root/mnt"
app=~/Library/Caches/luksfer-dev/dist/Luksfer.app/Contents/MacOS/Luksfer
export LUKSFER_TRASH_DIR="$root/trash" LUKSFER_SETTINGS_DIR="$root/settings" \
       LUKSFER_KEYCHAIN="$root/keychain/test.keychain-db" LUKSFER_MOUNT_DIR="$root/mnt"
LUKSFER_SELFTEST=1 LUKSFER_OPEN="$root/folder" "$app" 2>&1 | grep selftest
LUKSFER_SELFTEST=restore "$app" 2>&1 | grep selftest   # checks that the window comes back
# A launch to open a folder (`open -a Luksfer <folder>`) opens only that window. `open` does not pass the
# shell's environment, so each variable goes in with --env:
mkdir -p "$root/opened"
open -n -W --env LUKSFER_SELFTEST=opened --env LUKSFER_TRASH_DIR="$root/trash" \
     --env LUKSFER_SETTINGS_DIR="$root/settings" --env LUKSFER_KEYCHAIN="$root/keychain/test.keychain-db" \
     --env LUKSFER_MOUNT_DIR="$root/mnt" --stderr "$root/opened.log" \
     -a ~/Library/Caches/luksfer-dev/dist/Luksfer.app "$root/opened"
grep selftest "$root/opened.log"
```

- `LUKSFER_OPEN`: an empty folder to work in.
- `LUKSFER_TRASH_DIR`: a fake Trash.
- `LUKSFER_SETTINGS_DIR`: a settings folder.
- `LUKSFER_KEYCHAIN`: a keychain file the app makes, so test passwords never reach your login
  keychain.
- `LUKSFER_MOUNT_DIR`: where test network drives would mount, instead of `/Volumes`.

The Trash, keychain and mount switches count only in a self-test mode (`1`, `restore`, `opened`), and
each mode quits when it ends. A normal launch ignores them.

## Commits and pull requests

- English everywhere: app text, code, comments, commits and docs.
- One change per commit, with a subject that says what changed.
- Run the unit tests and the self-test before you open a pull request. CI runs the unit tests and
  builds the app on every push.
