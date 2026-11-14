#!/bin/bash
# Bina Sapu.app dan Sapu-$VERSION.dmg ke dalam dist/
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="1.0.0"
APP="dist/Sapu.app"

swift build -c release

rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Sapu "$APP/Contents/MacOS/Sapu"

ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
swift scripts/icon.swift "$ICONSET/base.png"
for s in 16 32 128 256 512; do
  sips -z $s $s "$ICONSET/base.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z $d $d "$ICONSET/base.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
rm "$ICONSET/base.png"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Sapu</string>
  <key>CFBundleDisplayName</key><string>Sapu</string>
  <key>CFBundleIdentifier</key><string>app.sapu.cleaner</string>
  <key>CFBundleExecutable</key><string>Sapu</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSDownloadsFolderUsageDescription</key><string>Sapu mencari fail besar dalam Downloads.</string>
  <key>NSDesktopFolderUsageDescription</key><string>Sapu mencari fail besar dalam Desktop.</string>
  <key>NSDocumentsFolderUsageDescription</key><string>Sapu mencari fail besar dalam Documents.</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"

STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Sapu" -srcfolder "$STAGE" -ov -format UDZO "dist/Sapu-$VERSION.dmg" >/dev/null
echo "Siap: dist/Sapu.app dan dist/Sapu-$VERSION.dmg"
