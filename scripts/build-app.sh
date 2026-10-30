#!/bin/zsh
# Builds Luksfer.app into ~/Library/Caches/luksfer-dev/dist/ (release; pass --debug for a debug build).
# Start it with: open ~/Library/Caches/luksfer-dev/dist/Luksfer.app
# LUKSFER_VERSION sets the version (default 0.1.0). LUKSFER_SIGN_IDENTITY picks the signing
# certificate; "-" signs ad hoc. LUKSFER_DIST changes the output folder.
set -eu
root="${0:A:h:h}"
config=release
[[ "${1:-}" == "--debug" ]] && config=debug
scratch="${LUKSFER_SCRATCH:-$HOME/Library/Caches/luksfer-dev/build/${root:t}}"
dist="${LUKSFER_DIST:-$HOME/Library/Caches/luksfer-dev/dist}"
app="$dist/Luksfer.app"

"$root/scripts/build.sh" -c "$config" --product Luksfer

rm -rf "$app"   # only ever our own build output
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$scratch/$config/Luksfer" "$app/Contents/MacOS/Luksfer"
for bundle in "$scratch/$config"/*.bundle(N); do cp -R "$bundle" "$app/Contents/Resources/"; done

# Icon: the Icon Composer file gives the macOS 26 look (Assets.car); the hand-made .icns keeps
# small sizes sharp on macOS 15.
xcrun actool "$root/Resources/AppIcon.icon" --compile "$app/Contents/Resources" \
  --platform macosx --minimum-deployment-target 15.0 --app-icon AppIcon \
  --output-partial-info-plist "$scratch/icon-partial.plist" > /dev/null
cp "$root/Resources/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"

# The licenses of the third-party code compiled into the app (SwiftTerm and what it includes).
cp "$root/THIRD_PARTY_NOTICES.md" "$app/Contents/Resources/THIRD_PARTY_NOTICES.md"

version="${LUKSFER_VERSION:-0.1.0}"
build_number=$(git -C "$root" rev-list --count HEAD 2>/dev/null || echo 1)
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>io.github.wawrepo.luksfer</string>
  <key>CFBundleName</key><string>Luksfer</string>
  <key>CFBundleDisplayName</key><string>Luksfer</string>
  <key>CFBundleExecutable</key><string>Luksfer</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$build_number</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticTermination</key><false/>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>Folder</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>LSItemContentTypes</key><array><string>public.folder</string></array>
    </dict>
  </array>
</dict>
</plist>
PLIST

# By default, sign with the local development certificate if there is one (macOS privacy
# permissions and Keychain access then stay across rebuilds), else ad hoc.
identity="${LUKSFER_SIGN_IDENTITY:-$(security find-identity -p codesigning -v 2>/dev/null | awk -F'"' '/Apple Development/ {print $2; exit}')}"
identity="${identity:--}"
codesign --force --sign "$identity" --timestamp=none "$app" 2> /dev/null
signed="ad hoc"
[[ "$identity" != "-" ]] && signed="certificate"
echo "Built $app ($config, version $version, build $build_number, signed: $signed)"
