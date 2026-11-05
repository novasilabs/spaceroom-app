#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Builds a Release Spaceroom.app and packages it as dist/Spaceroom-<version>.dmg.
# Local builds are ad-hoc signed; set SIGN_IDENTITY to a Developer ID to sign for
# distribution (notarize the resulting image with `xcrun notarytool` afterwards).
set -euo pipefail
cd "$(dirname "$0")/.."

SIGN_IDENTITY="${SIGN_IDENTITY:--}"
DERIVED=build/DerivedData
APP="$DERIVED/Build/Products/Release/Spaceroom.app"
STAGE=build/dmg-stage

echo "▸ Generating project"
xcodegen generate -q

echo "▸ Building Release"
xcodebuild -project Spaceroom.xcodeproj -scheme Spaceroom -configuration Release \
  -destination 'platform=macOS' -derivedDataPath "$DERIVED" \
  CODE_SIGN_IDENTITY="$SIGN_IDENTITY" build | grep -E "error:|warning:|BUILD" || true
[ -d "$APP" ] || { echo "Release build failed" >&2; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Contents/Info.plist")

echo "▸ Checking the signature"
codesign --verify --deep --strict --verbose=1 "$APP"

echo "▸ Staging"
rm -rf "$STAGE" && mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Spaceroom.app"
ln -s /Applications "$STAGE/Applications"
cp "scripts/Read Me First.txt" "$STAGE/Read Me First.txt"

echo "▸ Drawing the window background"
mkdir -p "$STAGE/.background"
swift scripts/dmg-background.swift build/dmg-art "$APP" >/dev/null
tiffutil -cathidpicheck build/dmg-art/background.png build/dmg-art/background@2x.png \
  -out "$STAGE/.background/background.tiff" 2>/dev/null

echo "▸ Creating the disk image"
mkdir -p dist
DMG="dist/Spaceroom-$VERSION.dmg"
RW="build/Spaceroom-rw.dmg"
rm -f "$DMG" "$RW"
hdiutil create -quiet -volname "Spaceroom $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$RW"
MOUNT=$(hdiutil attach -noverify -noautoopen "$RW" | awk -F'\t' '/\/Volumes\//{print $NF}')
DISK=$(basename "$MOUNT")

echo "▸ Laying out the window (macOS may ask to let this app control Finder)"
# Positions match scripts/dmg-background.swift (window content 660 × 500 points).
if ! osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$DISK"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 860, 648}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 112
    set text size of viewOptions to 13
    set background picture of viewOptions to file ".background:background.tiff"
    set position of item "Spaceroom.app" of container window to {180, 185}
    set position of item "Applications" of container window to {480, 185}
    set position of item "Read Me First.txt" of container window to {590, 412}
    close
    open
    update without registering applications
    delay 2
    close
  end tell
end tell
APPLESCRIPT
then
  echo "  (Finder layout skipped: allow control of Finder in System Settings › Privacy & Security › Automation)"
fi
# The volume icon goes in after Finder is done: Finder drops it while applying the layout.
if [ -f "$APP/Contents/Resources/AppIcon.icns" ]; then
  cp "$APP/Contents/Resources/AppIcon.icns" "$MOUNT/.VolumeIcon.icns"
  command -v SetFile >/dev/null && SetFile -a C "$MOUNT"
fi
chmod -Rf go-w "$MOUNT" 2>/dev/null || true
sync
hdiutil detach -quiet "$MOUNT" || { sleep 2; hdiutil detach -force -quiet "$MOUNT"; }
hdiutil convert -quiet "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG"
rm -f "$RW"
[ "$SIGN_IDENTITY" != "-" ] && codesign --sign "$SIGN_IDENTITY" --timestamp "$DMG"

hdiutil verify -quiet "$DMG"
(cd dist && shasum -a 256 "$(basename "$DMG")" | tee "$(basename "$DMG").sha256")
echo "✓ $DMG (version $VERSION, build $BUILD, $(du -h "$DMG" | cut -f1))"
