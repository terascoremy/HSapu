#!/bin/zsh
# Sign with Developer ID, notarize with Apple and staple the ticket to build/HSapu.app.
# Needs (env or scripts/signing.env):  SIGN_IDENTITY="Developer ID Application: Name (TEAMID)"  NOTARY_PROFILE="hstat-notary"
set -e; cd "$(dirname "$0")/.."
[ -f scripts/signing.env ] && source scripts/signing.env
: "${SIGN_IDENTITY:?set SIGN_IDENTITY}"; : "${NOTARY_PROFILE:?set NOTARY_PROFILE}"
./build_app.sh
ditto -ck --keepParent build/HSapu.app build/notarize.zip
xcrun notarytool submit build/notarize.zip --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple build/HSapu.app
rm -f build/notarize.zip
spctl -a -vv build/HSapu.app
