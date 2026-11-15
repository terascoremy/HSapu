#!/bin/zsh
# Usage: scripts/make_dmg.sh  → dist/HSapu-<version>.dmg (drag-to-Applications window, signed + notarized)
set -e; cd "$(dirname "$0")/.."
[ -f scripts/signing.env ] && source scripts/signing.env
[ -d build/HSapu.app ] || ./build_app.sh
NAME=HSapu; BG_TOP="#fdf2f8"; BG_BOTTOM="#e9d5ff"; INK="#4a0d33"
VER=$(grep -o "\"[0-9][0-9.]*\"" Sources/HSapu/Version.swift | head -1 | tr -d "\""); mkdir -p dist build
VOL="$NAME $VER"; OUT="dist/$NAME-$VER.dmg"; RW="build/$NAME-rw.dmg"
swift scripts/dmg_bg.swift build/dmg-bg.png "$NAME" "$BG_TOP" "$BG_BOTTOM" "$INK"
STAGE=$(mktemp -d)
cp -R build/$NAME.app "$STAGE/"; ln -s /Applications "$STAGE/Applications"
mkdir "$STAGE/.background"; cp build/dmg-bg.png "$STAGE/.background/bg.png"
rm -f "$RW" "$OUT"
hdiutil create -volname "$VOL" -srcfolder "$STAGE" -ov -format UDRW -fs HFS+ "$RW" >/dev/null
rm -rf "$STAGE"
DEV=$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | grep Apple_HFS | awk '{print $1}')
sleep 2
osascript <<OSA || echo "Finder layout skipped (no automation permission); DMG still works"
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 860, 520}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set text size of opts to 13
    set background picture of opts to file ".background:bg.png"
    set position of item "$NAME.app" to {170, 200}
    set position of item "Applications" to {490, 200}
    update without registering applications
    delay 2
    close
  end tell
end tell
OSA
sync; hdiutil detach "$DEV" >/dev/null || { sleep 3; hdiutil detach -force "$DEV" >/dev/null; }
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$OUT" >/dev/null
rm -f "$RW"
if [ -n "$SIGN_IDENTITY" ] && [ "$SIGN_IDENTITY" != "-" ]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$OUT"
  if [ -n "$NOTARY_PROFILE" ]; then
    xcrun notarytool submit "$OUT" ${=NOTARY_AUTH} --wait
    xcrun stapler staple "$OUT"
  fi
fi
echo "$OUT"
