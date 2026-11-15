#!/bin/zsh
# Build an UPDATE package (zip of HSapu.app, ~few MB) + checksum and optionally publish it as a GitHub release.
#   scripts/release.sh                 → builds dist/HSapu-update-<ver>.zip (+ .sha256), prints the publish command
#   scripts/release.sh --publish "Notes text"   → also runs `gh release create v<ver>` on terascoremy/HSapu
# Bump VERSION first (e.g. 1.0.1). The in-app updater downloads this zip, swaps the app and relaunches.
set -e; cd "$(dirname "$0")/.."
[ -f scripts/signing.env ] && source scripts/signing.env
if [ -n "$NOTARY_PROFILE" ]; then ./scripts/notarize.sh >/dev/null; else ./build_app.sh >/dev/null; fi
VER=$(grep -o "\"[0-9][0-9.]*\"" Sources/HSapu/Version.swift | head -1 | tr -d "\""); mkdir -p dist
ZIP="dist/HSapu-update-$VER.zip"
rm -f "$ZIP"; ditto -ck --keepParent build/HSapu.app "$ZIP"
(cd dist && shasum -a 256 "HSapu-update-$VER.zip" > "HSapu-update-$VER.zip.sha256")
echo "Built $ZIP ($(du -h "$ZIP" | cut -f1))"
if [ "$1" = "--publish" ]; then
  # GitHub only hosts what the in-app updater needs: the update zip and its checksum.
  gh release create "v$VER" "$ZIP" "$ZIP.sha256" --repo terascoremy/HSapu --title "HSapu $VER" --notes "${2:-Update $VER}"
  ./scripts/make_dmg.sh >/dev/null            # signed + notarized DMG, hosted on terascore.my/hsapu/files (not on GitHub)
  cp "dist/HSapu-$VER.dmg" dist/HSapu.dmg
  echo "DMG for terascore.my/hsapu/files: dist/HSapu-$VER.dmg (and dist/HSapu.dmg)"
else
  echo "Publish with: gh release create v$VER $ZIP $ZIP.sha256 --repo terascoremy/HSapu --title \"HSapu $VER\" --notes \"What's new…\""
fi
