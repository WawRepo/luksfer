#!/bin/zsh
# Builds the installable disk image: Luksfer-<version>.dmg (the app and a link to Applications)
# and Luksfer-<version>.dmg.sha256, in ~/Library/Caches/luksfer-dev/release/.
# Usage: scripts/release.sh [version]    e.g. scripts/release.sh v0.1.0
# Without a version it uses the newest v* git tag, else 0.1.0. The app is signed ad hoc unless
# LUKSFER_SIGN_IDENTITY names a certificate.
set -eu
root="${0:A:h:h}"
tag="${1:-$(git -C "$root" describe --tags --match 'v[0-9]*' --abbrev=0 2>/dev/null || echo 0.1.0)}"
version="${tag#v}"
if [[ ! "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$' ]]; then
  echo "release.sh: \"$tag\" is not a version like v0.1.0" >&2
  exit 1
fi
dist="$HOME/Library/Caches/luksfer-dev/release"   # apart from the everyday build in dist/
dmg="$dist/Luksfer-$version.dmg"
stage="$dist/dmg-stage"

LUKSFER_DIST="$dist" LUKSFER_VERSION="$version" LUKSFER_SIGN_IDENTITY="${LUKSFER_SIGN_IDENTITY:--}" "$root/scripts/build-app.sh"
codesign --verify --strict "$dist/Luksfer.app"

rm -rf "$stage" "$dmg" "$dmg.sha256"   # only ever our own build output
mkdir -p "$stage"
ditto "$dist/Luksfer.app" "$stage/Luksfer.app"
ln -s /Applications "$stage/Applications"
hdiutil create -quiet -volname "Luksfer $version" -srcfolder "$stage" -format UDZO "$dmg"
rm -rf "$stage"
(cd "$dist" && shasum -a 256 "${dmg:t}" > "${dmg:t}.sha256")
echo "Built $dmg"
cat "$dmg.sha256"
