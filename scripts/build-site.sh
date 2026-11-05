#!/bin/sh
# Puts the docs site (site/) and the images it uses into one new folder, ready for GitHub Pages.
# The images stay where the README uses them, so the repo holds each one once.
#   scripts/build-site.sh <new folder>
set -eu
out="${1:?usage: scripts/build-site.sh <new folder>}"
root="$(cd "$(dirname "$0")/.." && pwd)"
if [ -e "$out" ]; then
    echo "$out already exists. Give a new folder." >&2
    exit 1
fi
mkdir -p "$out/images"
cp -R "$root/site/." "$out/"
cp "$root/docs/brand/logo.png" "$root/docs/images/two-panes.png" "$root/docs/images/terminal.png" "$out/images/"
icons="$root/Resources/Assets.xcassets/AppIcon.appiconset"
cp "$icons/icon_32x32@2x.png" "$out/images/favicon.png"
cp "$icons/icon_128x128@2x.png" "$out/images/icon.png"
echo "site: $out"
