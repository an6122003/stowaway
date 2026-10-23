#!/bin/bash
# Produces a distributable Stowaway: dist/Stowaway-<version>.dmg and .zip
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Stowaway"
APP="build/$APP_NAME.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
DIST="dist"
DMG="$DIST/$APP_NAME-$VERSION.dmg"
ZIP="$DIST/$APP_NAME-$VERSION.zip"

./build.sh --universal

rm -rf "$DIST"
mkdir -p "$DIST"

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

cat > "$STAGING/Read Me First.txt" <<'NOTE'
Stowaway
========

1. Drag Stowaway.app onto the Applications folder in this window.
2. Open it. A small list icon appears at the right of your menu bar, and the
   other app icons are tucked away behind the notch.
3. Click that icon - or press Control-Option-Command-B anywhere - for a
   vertical list of every menu bar item, hidden ones included. Click a row to
   open that app's menu.

The list needs Accessibility permission, which you grant once in
System Settings > Privacy & Security > Accessibility. Stowaway uses it only to
read the menu bar items and to press the one you pick.

No root, no screen recording, no network access.

First launch
------------
Stowaway is not notarized by Apple, so macOS refuses the first launch. Allow it
under System Settings > Privacy & Security > "Open Anyway", or run:

   xattr -dr com.apple.quarantine /Applications/Stowaway.app
NOTE

hdiutil create \
	-volname "$APP_NAME" \
	-srcfolder "$STAGING" \
	-fs HFS+ \
	-format UDZO \
	-ov \
	"$DMG" >/dev/null

ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo
echo "Version $VERSION  ($(lipo -archs "$APP/Contents/MacOS/$APP_NAME"))"
ls -lh "$DMG" "$ZIP" | awk '{print "  " $9 "  " $5}'
echo
shasum -a 256 "$DMG" "$ZIP"
