#!/bin/zsh
# Usage: scripts/make_dmg.sh  → dist/HSapu-<version>.dmg
set -e; cd "$(dirname "$0")/.."
[ -f scripts/signing.env ] && source scripts/signing.env
[ -d build/HSapu.app ] || ./build_app.sh
VER=$(grep -o "\"[0-9][0-9.]*\"" Sources/HSapu/Version.swift | head -1 | tr -d "\""); mkdir -p dist; STAGE=$(mktemp -d)
cp -R build/HSapu.app "$STAGE/"; ln -s /Applications "$STAGE/Applications"
rm -f "dist/HSapu-$VER.dmg"
hdiutil create -volname "HSapu $VER" -srcfolder "$STAGE" -ov -format UDZO -fs HFS+ "dist/HSapu-$VER.dmg" >/dev/null
rm -rf "$STAGE"
if [ -n "$SIGN_IDENTITY" ] && [ "$SIGN_IDENTITY" != "-" ]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "dist/HSapu-$VER.dmg"
  if [ -n "$NOTARY_PROFILE" ]; then
    xcrun notarytool submit "dist/HSapu-$VER.dmg" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "dist/HSapu-$VER.dmg"
  fi
fi
echo "dist/HSapu-$VER.dmg"
