#!/bin/zsh
# Builds the installable disk image: Luksfer-<version>.dmg (the app and a link to Applications)
# and Luksfer-<version>.dmg.sha256, in ~/Library/Caches/luksfer-dev/release/.
# Usage: scripts/release.sh [version]    e.g. scripts/release.sh v0.1.0
# Without a version it uses the newest v* git tag, else 0.1.0. The app is signed ad hoc unless
# LUKSFER_SIGN_IDENTITY names a certificate.
# For a public release, set LUKSFER_SIGN_IDENTITY to a "Developer ID Application" certificate and
# LUKSFER_NOTARY_PROFILE to a profile made with `xcrun notarytool store-credentials`. The script
# then sends the disk image to Apple's notary service and attaches Apple's answer to the image,
# so macOS opens the app with no warning.
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
identity="${LUKSFER_SIGN_IDENTITY:--}"
notary="${LUKSFER_NOTARY_PROFILE:-}"
if [[ -n "$notary" && "$identity" != "Developer ID Application"* ]]; then
  echo 'release.sh: LUKSFER_NOTARY_PROFILE needs LUKSFER_SIGN_IDENTITY="Developer ID Application: ..."' >&2
  exit 1
fi

LUKSFER_DIST="$dist" LUKSFER_VERSION="$version" LUKSFER_SIGN_IDENTITY="$identity" "$root/scripts/build-app.sh"
codesign --verify --strict "$dist/Luksfer.app"

rm -rf "$stage" "$dmg" "$dmg.sha256"   # only ever our own build output
mkdir -p "$stage"
ditto "$dist/Luksfer.app" "$stage/Luksfer.app"
ln -s /Applications "$stage/Applications"
hdiutil create -quiet -volname "Luksfer $version" -srcfolder "$stage" -format UDZO "$dmg"
rm -rf "$stage"
if [[ -n "$notary" ]]; then
  codesign --force --sign "$identity" --timestamp "$dmg"
  # Apple gives a refused image no ticket, so stapling fails and the script stops with no checksum.
  xcrun notarytool submit "$dmg" --keychain-profile "$notary" --wait
  xcrun stapler staple "$dmg"
  spctl --assess --type open --context context:primary-signature --verbose "$dmg"
  spctl --assess --type execute --verbose "$dist/Luksfer.app"
fi
(cd "$dist" && shasum -a 256 "${dmg:t}" > "${dmg:t}.sha256")
echo "Built $dmg"
cat "$dmg.sha256"
