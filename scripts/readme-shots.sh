#!/bin/zsh
# Makes the README screenshots in docs/images/ from the real app, with made-up files.
# The demo home is on a sandbox disk image, so no real file, folder or disk size can show.
# Luksfer takes the screen focus for a few seconds per shot.
set -eu
root="${0:A:h:h}"
app="$HOME/Library/Caches/luksfer-dev/dist/Luksfer.app"
"$root/scripts/build-app.sh"

box=$(mktemp -d "$HOME/Library/Caches/luksfer-dev/sandbox/readme-shots.XXXXXX")
hdiutil create -quiet -type SPARSE -fs APFS -size 120g -volname Demo "$box/demo.sparseimage"
hdiutil attach -quiet -nobrowse -mountpoint "$box/mnt" "$box/demo.sparseimage"
trap 'hdiutil detach -quiet "$box/mnt" 2>/dev/null || true; rm -rf "$box"' EXIT

home="$box/mnt/alex"
projects="$home/Projects"
downloads="$home/Downloads"
mkdir -p "$home"/{Desktop,Documents,Pictures}

file() { # date size path
  mkdir -p "${3:h}"
  mkfile -n "$2" "$3"
  touch -t "$1" "$3"
}
file 202610141012 48k    "$projects/Garden Planner/plan.md"
file 202610201640 12k    "$projects/Recipe Book/soups.md"
file 202609021130 20k    "$projects/Website/index.html"
file 202608111505 8k     "$projects/Archive/old-notes.txt"
file 202610281622 186k   "$projects/budget-2026.xlsx"
file 202610300914 2400k  "$projects/client-presentation.key"
file 202611011745 14k    "$projects/meeting-notes.md"
file 202610221033 860k   "$projects/project-report.pdf"
file 202609180851 340k   "$projects/team-logo.png"
file 202611020930 3k     "$projects/todo.txt"
file 202608300812 48m    "$projects/website-backup.zip"
file 202610181120 1m     "$downloads/sample-data/rows.csv"
file 202610291842 3200k  "$downloads/beach-sunset.jpg"
file 202610120955 74m    "$downloads/intro-video.mp4"
file 202611021012 96k    "$downloads/invoice-0042.pdf"
file 202609270920 6200k  "$downloads/podcast-episode-12.mp3"
file 202610051418 128m   "$downloads/photo-editor-3.2.dmg"
file 202610310730 412k   "$downloads/train-tickets.pdf"
touch -t 202610141012 "$projects/Garden Planner"
touch -t 202610201640 "$projects/Recipe Book"
touch -t 202609021130 "$projects/Website"
touch -t 202608111505 "$projects/Archive"
touch -t 202610181120 "$downloads/sample-data"

# 80 columns, because the terminal has no tab stops past column 80 yet and wide `ls` output wraps.
cat > "$home/.zshrc" <<'ZSH'
PROMPT='%~ %# '
print -P "${PROMPT}ls"
COLUMNS=80 ls
ZSH

shoot() { # name twoPanes terminalOpen panes
  local settings="$box/settings-$1"
  mkdir -p "$settings"
  cat > "$settings/settings.json" <<JSON
{"favorites":[{"path":"$projects","label":"Projects"},{"path":"$downloads","label":"Downloads"},
  {"path":"$home/Documents","label":"Documents"}],
 "newWindowHotKey":false,"collapsedSidebarSections":["Locations"],
 "windows":[{"frame":"{{120, 120}, {1360, 760}}","twoPanes":$2,"activePane":0,"terminalOpen":$3,
   "terminalHeight":230,"sidebarWidth":190,"panes":[$4]}]}
JSON
  # ZDOTDIR too, or the shell reads the startup files of whoever runs this script.
  open -n -W --env CFFIXED_USER_HOME="$home" --env ZDOTDIR="$home" --env LUKSFER_SETTINGS_DIR="$settings" \
       --env LUKSFER_SNAPSHOT="$box/$1.png" --env LUKSFER_SNAPSHOT_REAL=1 \
       --env LUKSFER_SNAPSHOT_DELAY=4 --env LUKSFER_SNAPSHOT_QUIT=1 \
       -a "$app" --args -AppleLocale en_GB
  # sRGB in place of the display's color profile, which can name the display.
  sips -m "/System/Library/ColorSync/Profiles/sRGB Profile.icc" "$box/$1.png" --out "$root/docs/images/$1.png" > /dev/null
}
pane() { echo "{\"path\":\"$1\",\"sort\":{\"key\":\"name\",\"ascending\":true}}"; }

mkdir -p "$root/docs/images"
shoot two-panes true false "$(pane "$projects"),$(pane "$downloads")"
shoot terminal false true "$(pane "$projects")"
echo "Wrote docs/images/two-panes.png and docs/images/terminal.png"
