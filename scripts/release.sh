#!/bin/zsh
# Builds Fokly for distribution: Developer ID signed, hardened runtime, packaged as a DMG with
# its install window, notarized by Apple and stapled, signed for Sparkle and added to the
# update feed (site/appcast.xml).
#
# One-time setup:
#   xcrun notarytool store-credentials fokly-notary --apple-id <your Apple ID> --team-id P65VQHHXCB
#   Sparkle's EdDSA key lives in the login keychain (account "fokly"). Back it up:
#   build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys --account fokly -x <file>
#
# Usage: set the version in project.yml, write scripts/notes/<version>.html, then
#   scripts/release.sh            (or NOTARY_PROFILE=other scripts/release.sh)
# and publish, in this order (the feed must not point at a release that doesn't exist yet):
#   gh release create vX.Y dist/Fokly-X.Y.dmg dist/Fokly.dmg   (the website links to Fokly.dmg)
#   git commit site/appcast.xml && git push                     (Vercel deploys the feed)
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
PROFILE=${NOTARY_PROFILE:-fokly-notary}
IDENTITY="Developer ID Application"
APP=build/Build/Products/Release/Fokly.app
SPARKLE_BIN=build/SourcePackages/artifacts/sparkle/Sparkle/bin

xcodegen generate -q
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Fokly/Info.plist)
NOTES=scripts/notes/$VERSION.html
DMG=dist/Fokly-$VERSION.dmg
[[ -f "$NOTES" ]] || { echo "write $NOTES first"; exit 1; }

echo "→ Building Fokly $VERSION (release, no dev tools)"
xcodebuild -project Fokly.xcodeproj -scheme Fokly -configuration Release -derivedDataPath build \
  -skipMacroValidation -skipPackagePluginValidation build -quiet

echo "→ Signing Sparkle's helpers with Developer ID, inside out"
FW="$APP/Contents/Frameworks/Sparkle.framework"
sign() { codesign --force --sign "$IDENTITY" --options runtime --timestamp "$@"; }
sign "$FW/Versions/B/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$FW/Versions/B/XPCServices/Downloader.xpc"
sign "$FW/Versions/B/Autoupdate"
sign "$FW/Versions/B/Updater.app"
sign "$FW"
sign --preserve-metadata=entitlements,requirements,flags "$APP"

echo "→ Verifying signature"
codesign --verify --deep --strict --verbose=1 "$APP"
SIGNATURE=$(codesign -dv "$APP" 2>&1)
[[ "$SIGNATURE" == *"(runtime)"* ]] || { echo "hardened runtime missing"; exit 1; }
[[ "$(codesign -dv --verbose=2 "$FW/Versions/B/Updater.app" 2>&1)" == *"Developer ID"* ]] || { echo "Sparkle helpers not signed"; exit 1; }
[[ "$(strings "$APP/Contents/MacOS/Fokly")" != *"--stress"* ]] || { echo "dev tools leaked into release"; exit 1; }

echo "→ Packaging $DMG"
mkdir -p dist && rm -f "$DMG"
ART=$(mktemp -d)
python3 scripts/dmg/background.py "$ART"
uvx --from dmgbuild dmgbuild -s scripts/dmg/settings.py -D app="$APP" -D background="$ART/background.png" Fokly "$DMG" > /dev/null
rm -rf "$ART"
codesign --sign "$IDENTITY" --timestamp "$DMG"

if [[ "${SKIP_NOTARIZE:-0}" == 1 ]]; then echo "→ Skipping notarization"; exit 0; fi
echo "→ Notarizing (a few minutes)"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"
cp "$DMG" dist/Fokly.dmg

echo "→ Signing for Sparkle and adding $VERSION to the update feed"
ED=$("$SPARKLE_BIN/sign_update" --account fokly -p "$DMG")
python3 scripts/appcast.py "$APP" "$DMG" "$ED" "$NOTES"
echo "✓ $DMG is signed, notarized and ready to ship"
