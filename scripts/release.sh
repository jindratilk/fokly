#!/bin/zsh
# Builds Fokly for distribution: Developer ID signed, hardened runtime, packaged as a DMG,
# notarized by Apple and stapled, so it opens on any Mac without warnings.
#
# One-time setup (stores your notarization credentials in the keychain):
#   xcrun notarytool store-credentials fokly-notary --apple-id <your Apple ID> --team-id P65VQHHXCB
#
# Usage: scripts/release.sh            (or NOTARY_PROFILE=other scripts/release.sh)
# Then: gh release create vX.Y dist/Fokly-X.Y.dmg plus a copy named Fokly.dmg (the website links to that name).
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
PROFILE=${NOTARY_PROFILE:-fokly-notary}
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Fokly/Info.plist)
APP=build/Build/Products/Release/Fokly.app
DMG=dist/Fokly-$VERSION.dmg

echo "→ Building Fokly $VERSION (release, no dev tools)"
xcodegen generate -q
xcodebuild -project Fokly.xcodeproj -scheme Fokly -configuration Release -derivedDataPath build \
  -skipMacroValidation -skipPackagePluginValidation build -quiet

echo "→ Verifying signature"
codesign --verify --deep --strict --verbose=1 "$APP"
SIGNATURE=$(codesign -dv "$APP" 2>&1)
[[ "$SIGNATURE" == *"(runtime)"* ]] || { echo "hardened runtime missing"; exit 1; }
[[ "$(strings "$APP/Contents/MacOS/Fokly")" != *"--stress"* ]] || { echo "dev tools leaked into release"; exit 1; }

echo "→ Packaging $DMG"
mkdir -p dist && rm -f "$DMG"
STAGE=$(mktemp -d)
ditto "$APP" "$STAGE/Fokly.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "Fokly" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"
codesign --sign "Developer ID Application" --timestamp "$DMG"

if [[ "${SKIP_NOTARIZE:-0}" == 1 ]]; then echo "→ Skipping notarization"; exit 0; fi
echo "→ Notarizing (a few minutes)"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"
echo "✓ $DMG is signed, notarized and ready to ship"
