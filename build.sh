#!/bin/bash
# Builds "RetroCal.app" into ./build (debug by default, `./build.sh release` for an optimised build).
set -e
cd "$(dirname "$0")"
MODE="${1:-debug}"
APP="build/RetroCal.app"

# Release builds are Universal (Intel + Apple Silicon); debug stays native for speed.
ARCH=""; [ "$MODE" = "release" ] && ARCH="--arch arm64 --arch x86_64"
swift build -c "$MODE" $ARCH 2>&1 | tail -3
BIN="$(swift build -c "$MODE" $ARCH --show-bin-path | tail -1)/RetroCal"

rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/RetroCal"
cp Info.plist "$APP/Contents/Info.plist"

# App icon from the supplied PNG (scaled into an iconset; the source is 600 px, the largest sizes are upscaled)
ICONSET="$(mktemp -d)/AppIcon.iconset"; mkdir -p "$ICONSET"
for s in 16 32 64 128 256 512 1024; do sips -z $s $s Resources/AppIcon-source.png --out "$ICONSET/_$s.png" >/dev/null; done
cp "$ICONSET/_16.png"   "$ICONSET/icon_16x16.png";      cp "$ICONSET/_32.png"  "$ICONSET/icon_16x16@2x.png"
cp "$ICONSET/_32.png"   "$ICONSET/icon_32x32.png";      cp "$ICONSET/_64.png"  "$ICONSET/icon_32x32@2x.png"
cp "$ICONSET/_128.png"  "$ICONSET/icon_128x128.png";    cp "$ICONSET/_256.png" "$ICONSET/icon_128x128@2x.png"
cp "$ICONSET/_256.png"  "$ICONSET/icon_256x256.png";    cp "$ICONSET/_512.png" "$ICONSET/icon_256x256@2x.png"
cp "$ICONSET/_512.png"  "$ICONSET/icon_512x512.png";    cp "$ICONSET/_1024.png" "$ICONSET/icon_512x512@2x.png"
rm "$ICONSET"/_*.png
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# Signature: release → Developer ID (hardened runtime, timestamp); debug → a stable development identity (keeps the Calendars
# permission across rebuilds), else ad-hoc.
if [ "$MODE" = "release" ]; then
  SIGN="Developer ID Application: Maik Klotz (FTJLR8JRNS)"
  security find-identity -v -p codesigning | grep -q "$SIGN" || { echo "Developer ID certificate not found"; exit 1; }
  codesign --force --sign "$SIGN" --options runtime --timestamp --entitlements RetroCal.entitlements "$APP"
else
  SIGN="-"
  for id in "Apple Development: Maik Klotz (VB63U5MZD7)" "Developer ID Application: Maik Klotz (FTJLR8JRNS)"; do
    if security find-identity -v -p codesigning 2>/dev/null | grep -q "$id"; then SIGN="$id"; break; fi
  done
  codesign --force --sign "$SIGN" --entitlements RetroCal.entitlements "$APP" 2>&1 | tail -1
fi
echo "Built: $APP (signed: $SIGN)"
