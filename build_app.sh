#!/bin/zsh
set -e
cd "$(dirname "$0")"
[ -f scripts/signing.env ] && source scripts/signing.env   # SIGN_IDENTITY / NOTARY_PROFILE (not committed)
VER=$(grep -o '"[0-9][0-9.]*"' Sources/HSapu/Version.swift | head -1 | tr -d '"')
[ -n "$VER" ] || { echo "Version not found in Version.swift"; exit 1; }
swift build -c release --arch arm64 --arch x86_64
BIN=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/HSapu
APP=build/HSapu.app
BUILD=$(date +%Y%m%d%H%M)
rm -rf $APP build/icon.iconset && mkdir -p $APP/Contents/MacOS $APP/Contents/Resources build/icon.iconset
cp $BIN $APP/Contents/MacOS/HSapu
swift scripts/icon.swift build/icon.iconset/base.png
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon.iconset/base.png --out build/icon.iconset/icon_${s}x${s}.png >/dev/null
  d=$((s * 2)); sips -z $d $d build/icon.iconset/base.png --out build/icon.iconset/icon_${s}x${s}@2x.png >/dev/null
done
rm build/icon.iconset/base.png
iconutil -c icns build/icon.iconset -o $APP/Contents/Resources/AppIcon.icns
cat > $APP/Contents/Info.plist <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>HSapu</string>
<key>CFBundleDisplayName</key><string>HSapu</string>
<key>CFBundleIdentifier</key><string>com.hsapu.app</string>
<key>CFBundleExecutable</key><string>HSapu</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>$BUILD</string>
<key>CFBundleShortVersionString</key><string>$VER</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>© 2026 Teras Core Technology Sdn. Bhd.</string>
<key>NSDownloadsFolderUsageDescription</key><string>HSapu mencari fail besar dalam Downloads.</string>
<key>NSDesktopFolderUsageDescription</key><string>HSapu mencari fail besar dalam Desktop.</string>
<key>NSDocumentsFolderUsageDescription</key><string>HSapu mencari fail besar dalam Documents.</string>
</dict></plist>
PL
IDENTITY="${SIGN_IDENTITY:--}"
if [ "$IDENTITY" = "-" ]; then
  codesign --force --deep --sign - $APP
  echo "Signed ad-hoc (no Developer ID)"
else
  codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" $APP
  codesign --verify --strict --verbose=2 $APP
  echo "Signed with: $IDENTITY"
fi
echo "Built $APP"
