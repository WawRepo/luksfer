#!/bin/zsh
# Builds Okno.app into ~/Library/Caches/okno-dev/dist/ (release; pass --debug for a debug build).
# Start it with: open ~/Library/Caches/okno-dev/dist/Okno.app
set -eu
root="${0:A:h:h}"
config=release
[[ "${1:-}" == "--debug" ]] && config=debug
scratch="${OKNO_SCRATCH:-$HOME/Library/Caches/okno-dev/build/${root:t}}"
dist="$HOME/Library/Caches/okno-dev/dist"
app="$dist/Okno.app"

"$root/scripts/build.sh" -c "$config" --product Okno

rm -rf "$app"   # only ever our own build output
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$scratch/$config/Okno" "$app/Contents/MacOS/Okno"
for bundle in "$scratch/$config"/*.bundle(N); do cp -R "$bundle" "$app/Contents/Resources/"; done

# Icon: the Icon Composer file gives the macOS 26 look (Assets.car); the hand-made .icns keeps
# small sizes sharp on macOS 15.
xcrun actool "$root/Resources/AppIcon.icon" --compile "$app/Contents/Resources" \
  --platform macosx --minimum-deployment-target 15.0 --app-icon AppIcon \
  --output-partial-info-plist "$scratch/icon-partial.plist" > /dev/null
cp "$root/Resources/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"

# The licenses of the third-party code compiled into the app (SwiftTerm and what it includes).
cp "$root/THIRD_PARTY_NOTICES.md" "$app/Contents/Resources/THIRD_PARTY_NOTICES.md"

build_number=$(git -C "$root" rev-list --count HEAD 2>/dev/null || echo 1)
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>app.okno.Okno</string>
  <key>CFBundleName</key><string>Okno</string>
  <key>CFBundleDisplayName</key><string>Okno</string>
  <key>CFBundleExecutable</key><string>Okno</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
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

# Sign with the local development certificate if there is one (keeps macOS privacy
# permissions across rebuilds), else ad hoc.
identity=$(security find-identity -p codesigning -v 2>/dev/null | awk -F'"' '/Apple Development/ {print $2; exit}')
codesign --force --sign "${identity:--}" --timestamp=none "$app" 2> /dev/null
signed="ad hoc"
[[ -n "$identity" ]] && signed="development certificate"
echo "Built $app ($config, build $build_number, signed: $signed)"
