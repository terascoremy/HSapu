#!/bin/bash
# Tanda tangan dengan Developer ID, hantar ke Apple untuk notarize, dan staple.
# Perlukan akaun Apple Developer (berbayar). Tanpa ini Sapu hanya bertanda tangan ad-hoc
# dan Gatekeeper akan beri amaran (klik kanan > Open).
#
# Sekali sahaja, simpan kelayakan dalam Keychain:
#   xcrun notarytool store-credentials sapu-notary --apple-id <emel> --team-id <TEAMID> --password <app-specific-password>
#
# Kemudian:
#   SIGN_ID="Developer ID Application: Nama Kau (TEAMID)" ./scripts/notarize.sh
set -euo pipefail
cd "$(dirname "$0")/.."
: "${SIGN_ID:?Set SIGN_ID kepada nama sijil Developer ID Application}"
PROFILE="${NOTARY_PROFILE:-sapu-notary}"

SIGN_ID="$SIGN_ID" ./scripts/build.sh
DMG=$(ls dist/Sapu-*.dmg | head -1)

echo "Hantar $DMG untuk notarize (boleh ambil beberapa minit)..."
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature -v "$DMG" || true
echo "Siap: $DMG sudah di-notarize."
