#!/bin/bash
# Builds Stowaway.app into ./build (no Xcode project needed).
#
#   ./build.sh              host architecture only (fast, for development)
#   ./build.sh --universal  arm64 + x86_64 universal binary (for distribution)
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Stowaway"
APP="build/$APP_NAME.app"
SOURCES=(Sources/GlobalHotKey.swift Sources/MenuBarItems.swift Sources/AppDelegate.swift Sources/main.swift)
DEPLOYMENT_TARGET="13.0"

if [[ "${1:-}" == "--universal" ]]; then
	ARCHS=(arm64 x86_64)
else
	ARCHS=("$(uname -m)")
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

SLICES=()
for arch in "${ARCHS[@]}"; do
	echo "Compiling $arch…"
	slice="build/$APP_NAME-$arch"
	swiftc -O \
		-target "${arch}-apple-macos${DEPLOYMENT_TARGET}" \
		-o "$slice" \
		"${SOURCES[@]}"
	SLICES+=("$slice")
done

if [[ ${#SLICES[@]} -gt 1 ]]; then
	lipo -create -output "$APP/Contents/MacOS/$APP_NAME" "${SLICES[@]}"
else
	mv "${SLICES[0]}" "$APP/Contents/MacOS/$APP_NAME"
fi
rm -f "${SLICES[@]}"

# Use a Developer ID certificate when one exists, otherwise sign ad-hoc.
# A stable identity matters here: an ad-hoc signature changes on every build,
# so macOS treats each rebuild as a different app and the Accessibility grant
# goes stale — the checkbox stays ticked while the app is no longer trusted.
# Any real certificate keeps the identity constant across rebuilds.
# Returns the SHA-1 of the first valid matching certificate. The hash, not the
# name: several certificates can share a common name (expired or revoked ones
# linger), and codesign refuses an ambiguous name.
pick_identity() {
	local pattern="$1"
	security find-identity -v -p codesigning 2>/dev/null \
		| grep -v CSSMERR \
		| grep "$pattern" \
		| head -1 \
		| awk '{print $2}' || true
}

# Public builds sign ad-hoc on purpose: a development certificate embeds its
# owner's name and email in the signature of every binary it signs.
#   STOWAWAY_SIGN=adhoc ./package.sh
if [[ "${STOWAWAY_SIGN:-}" == "adhoc" ]]; then
	IDENTITY=""
else
	IDENTITY="$(pick_identity 'Developer ID Application: ')"
fi
if [[ "${STOWAWAY_SIGN:-}" != "adhoc" ]]; then
	[[ -z "$IDENTITY" ]] && IDENTITY="$(pick_identity 'Apple Development: ')"
	[[ -z "$IDENTITY" ]] && IDENTITY="$(pick_identity 'Stowaway Local Signing')"
fi

if [[ -n "$IDENTITY" ]]; then
	echo "Signing with: $IDENTITY"
	codesign --force --deep --sign "$IDENTITY" "$APP"
else
	echo "No stable identity — signing ad-hoc."
	echo "  Accessibility permission will need re-granting after every rebuild."
	echo "  Fix once with: ./scripts/make-signing-identity.sh"
	codesign --force --sign - "$APP"
fi

codesign --verify --strict "$APP"
echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/$APP_NAME"))"
