#!/bin/bash
# Creates a local code signing certificate ("RightHand Local Signing") in your login keychain.
# Builds signed with it look like the same app to macOS, so permissions (Desktop folder,
# browser control, Keychain items) are kept after every rebuild instead of being asked again.
# Run once: scripts/setup-signing.sh
set -euo pipefail

NAME="RightHand Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "“$NAME” already exists."
    exit 0
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
PASSWORD=$(uuidgen)

cat > "$WORK/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$WORK/cert.cnf" \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null
# -legacy: macOS's `security` can't read OpenSSL 3+'s default PKCS#12 encryption.
LEGACY=$(openssl version | grep -qE '^OpenSSL [3-9]' && echo -legacy || true)
openssl pkcs12 -export $LEGACY -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -name "$NAME" -out "$WORK/identity.p12" -passout "pass:$PASSWORD"

# -T lets codesign use the key without asking.
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$PASSWORD" -T /usr/bin/codesign >/dev/null
echo "Created “$NAME”. Builds are now signed with it."
