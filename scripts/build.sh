#!/bin/bash
# Bina Sapu.app dan Sapu-$VERSION.dmg ke dalam dist/
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(grep -o '"[0-9][0-9.]*"' Sources/Sapu/Version.swift | head -1 | tr -d '"')
[ -n "$VERSION" ] || { echo "Versi tak dijumpai dalam Version.swift"; exit 1; }
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

# Tanda tangan. Identiti yang SAMA pada setiap versi membuat macOS ingat kebenaran folder
# (Desktop, Documents, Downloads, Akses Cakera Penuh). Tanda tangan ad-hoc berubah setiap
# binaan, jadi kebenaran diminta semula setiap kali.
#   SIGN_ID="Nama sijil"  guna sijil itu (Developer ID juga dapat hardened runtime + timestamp)
#   SIGN_ID=-             paksa ad-hoc
#   (kosong)              cari sijil "Apple Development" dalam Keychain, jika tiada guna ad-hoc
if [ -z "${SIGN_ID:-}" ]; then
  SIGN_ID=$(security find-identity -v -p codesigning | grep -m1 "Apple Development" | sed -E 's/.*"(.*)".*/\1/' || true)
  SIGN_ID="${SIGN_ID:--}"
fi
if [ "$SIGN_ID" = "-" ]; then
  echo "Tanda tangan: ad-hoc (kebenaran folder akan diminta semula selepas setiap kemas kini)"
  codesign --force --deep --sign - "$APP"
elif [[ "$SIGN_ID" == Developer\ ID* ]]; then
  echo "Tanda tangan: $SIGN_ID (hardened runtime)"
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_ID" "$APP"
else
  echo "Tanda tangan: $SIGN_ID"
  codesign --force --deep --timestamp=none --sign "$SIGN_ID" "$APP"
fi

STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Sapu" -srcfolder "$STAGE" -ov -format UDZO "dist/Sapu-$VERSION.dmg" >/dev/null
echo "Siap: dist/Sapu.app dan dist/Sapu-$VERSION.dmg"
