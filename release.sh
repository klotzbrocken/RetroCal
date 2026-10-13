#!/bin/bash
# Release build, Developer ID signature and DMG:  ./release.sh   ->  RetroCal-<version>.dmg
# Add --notarize to submit it to Apple (needs: xcrun notarytool store-credentials "Retromac" ...) and staple the ticket.
set -e
cd "$(dirname "$0")"
./build.sh release
APP="build/RetroCal.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="RetroCal-$VERSION.dmg"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"; ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "RetroCal" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
codesign --force --sign "Developer ID Application: Maik Klotz (FTJLR8JRNS)" --timestamp "$DMG"
if [ "$1" = "--notarize" ]; then
  xcrun notarytool submit "$DMG" --keychain-profile "Retromac" --wait
  xcrun stapler staple "$DMG"
fi
echo "DMG: $(pwd)/$DMG ($(du -h "$DMG" | cut -f1))"
