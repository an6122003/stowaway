#!/bin/bash
# Creates a self-signed code-signing identity so rebuilds keep their identity.
#
#   ./scripts/make-signing-identity.sh
#
# Why: an ad-hoc signature ( codesign -s - ) hashes the binary, so every
# rebuild looks like a different app and macOS revokes the Accessibility
# permission you granted. A stable identity keeps the grant across rebuilds.
#
# This adds one certificate to your login keychain and nothing else. Remove it
# any time in Keychain Access, or with:
#   security delete-certificate -c "Stowaway Local Signing"
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="Stowaway Local Signing"

if security find-identity -v -p codesigning | grep -q "$NAME"; then
	echo "Identity '$NAME' already exists."
	exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
	-keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
	-subj "/CN=$NAME" \
	-addext "basicConstraints=critical,CA:false" \
	-addext "keyUsage=critical,digitalSignature" \
	-addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null

openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
	-out "$WORK/identity.p12" -passout pass: -name "$NAME"

# -A lets codesign use the key without a prompt on every build.
security import "$WORK/identity.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
	-P "" -A -T /usr/bin/codesign

echo "Created '$NAME'. Rebuilds will now keep the same identity."
echo "Run ./build.sh and re-grant Accessibility once; it will stick from then on."
