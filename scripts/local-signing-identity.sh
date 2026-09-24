#!/bin/bash
# CatCleaner local-only stable code-signing identity.
#
# This identity is intentionally NOT a Developer ID and is only for builds used
# on this Mac. It gives local installs a stable designated signing identity so
# TCC/FDA permissions do not churn on every rebuild.
#
# Usage:
#   ./scripts/local-signing-identity.sh --ensure
#   ./scripts/local-signing-identity.sh --check
#   ./scripts/local-signing-identity.sh --sign /path/to/CatCleaner.app

set -euo pipefail

MODE="${1:---check}"
APP_PATH="${2:-}"

IDENTITY="CatCleaner Local Code Signing"
KEYCHAIN="$HOME/Library/Keychains/CatCleanerLocalSigning.keychain-db"
SERVICE="CatCleaner Local Signing Keychain Password"
ACCOUNT="${USER:-catcleaner}"
SIGN_DIR="$HOME/Library/Application Support/CatCleaner/Signing"
KEY_FILE="$SIGN_DIR/local-code-signing-private-key.pem"
CERT_FILE="$SIGN_DIR/local-code-signing-certificate.pem"
P12_FILE="$SIGN_DIR/local-code-signing-backup.p12"

die() {
  echo "LOCAL_SIGNING_IDENTITY_FAIL: $*" >&2
  exit 1
}

password() {
  security find-generic-password -s "$SERVICE" -a "$ACCOUNT" -w 2>/dev/null
}

identity_line() {
  security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null |
    awk -v expected="$IDENTITY" -F'"' '$2 == expected { print; exit }'
}

unlock_keychain() {
  local pw
  pw="$(password)" || die "keychain password is unavailable"
  security unlock-keychain -p "$pw" "$KEYCHAIN" >/dev/null
}

check_identity() {
  [[ -f "$KEYCHAIN" ]] || die "dedicated keychain is missing: $KEYCHAIN"
  unlock_keychain

  local line
  line="$(identity_line)"
  [[ -n "$line" ]] || die "code-signing identity not found in dedicated keychain"

  local count
  count="$(
    security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null |
      awk -v expected="$IDENTITY" -F'"' '$2 == expected { n++ } END { print n+0 }'
  )"
  [[ "$count" == "1" ]] || die "expected exactly one local identity; count=$count"

  echo "CATCLEANER_LOCAL_SIGNING_IDENTITY_PASS"
  echo "identity=$IDENTITY"
  echo "keychain=$KEYCHAIN"
}

ensure_identity() {
  if [[ -f "$KEYCHAIN" ]]; then
    unlock_keychain
    if [[ -z "$(identity_line)" && -f "$CERT_FILE" ]]; then
      # Self-signed identities are not considered valid by Security.framework
      # until the user trust domain explicitly trusts this certificate for the
      # code-signing policy. This does not touch the system/admin trust store.
      security add-trusted-cert         -r trustRoot -p codeSign         -k "$KEYCHAIN" "$CERT_FILE" >/dev/null
    fi
    check_identity
    return
  fi

  if security find-generic-password -s "$SERVICE" -a "$ACCOUNT" >/dev/null 2>&1; then
    die "password record exists but dedicated keychain does not; refusing ambiguous recovery"
  fi

  mkdir -p "$SIGN_DIR"
  chmod 700 "$SIGN_DIR"

  local pw
  pw="$(/usr/bin/openssl rand -base64 48 | tr -d '\n')"
  [[ -n "$pw" ]] || die "failed to generate keychain password"

  security add-generic-password     -s "$SERVICE" -a "$ACCOUNT" -w "$pw" >/dev/null

  if ! security create-keychain -p "$pw" "$KEYCHAIN" >/dev/null; then
    security delete-generic-password -s "$SERVICE" -a "$ACCOUNT" >/dev/null 2>&1 || true
    die "failed to create dedicated signing keychain"
  fi

  # Local key material is encrypted at rest. The backup is intentionally kept
  # outside the repository so the identity can be restored without regeneration.
  /usr/bin/openssl genrsa     -aes256 -passout pass:"$pw" -out "$KEY_FILE" 2048 >/dev/null 2>&1
  chmod 600 "$KEY_FILE"

  /usr/bin/openssl req -x509 -new -sha256 -days 3650     -key "$KEY_FILE" -passin pass:"$pw"     -out "$CERT_FILE"     -subj "/C=TW/O=CatCleaner/CN=$IDENTITY"     -addext "basicConstraints=critical,CA:FALSE"     -addext "keyUsage=critical,digitalSignature"     -addext "extendedKeyUsage=codeSigning"
  chmod 600 "$CERT_FILE"

  /usr/bin/openssl pkcs12 -export     -inkey "$KEY_FILE" -passin pass:"$pw"     -in "$CERT_FILE"     -name "$IDENTITY"     -out "$P12_FILE" -passout pass:"$pw"
  chmod 600 "$P12_FILE"

  if ! security import "$P12_FILE"       -k "$KEYCHAIN" -P "$pw"       -T /usr/bin/codesign -T /usr/bin/security >/dev/null; then
    die "failed to import local signing identity"
  fi

  security set-keychain-settings -lut 21600 "$KEYCHAIN" >/dev/null
  security unlock-keychain -p "$pw" "$KEYCHAIN" >/dev/null

  # Trust only this self-signed certificate for the user-domain code-signing
  # policy. It is not installed as a system/admin root and is not a Developer ID.
  security add-trusted-cert     -r trustRoot -p codeSign     -k "$KEYCHAIN" "$CERT_FILE" >/dev/null

  # Permit Apple code-signing tooling to use the private key non-interactively.
  security set-key-partition-list     -S apple-tool:,apple:,codesign:     -s -k "$pw" "$KEYCHAIN" >/dev/null 2>&1 ||
    die "failed to set code-signing key ACL"

  check_identity
}

sign_app() {
  [[ -n "$APP_PATH" ]] || die "--sign requires an app path"
  [[ -d "$APP_PATH" ]] || die "app bundle not found: $APP_PATH"

  check_identity >/dev/null
  unlock_keychain

  local menu="$APP_PATH/Contents/Library/LoginItems/MacCleanMenu.app"
  local battery_helper="$APP_PATH/Contents/MacOS/CatCleanerBatteryHelper"
  local entitlements
  entitlements="$(cd "$(dirname "$0")/.." && pwd)/.build/entitlements.plist"

  [[ -d "$menu" ]] || die "nested menu app missing: $menu"
  [[ -x "$battery_helper" ]] || die "battery helper missing: $battery_helper"
  [[ -f "$entitlements" ]] || die "entitlements missing: $entitlements"

  codesign --force     --keychain "$KEYCHAIN"     --sign "$IDENTITY"     --timestamp=none     "$battery_helper"

  codesign --force     --keychain "$KEYCHAIN"     --sign "$IDENTITY"     --timestamp=none     "$menu"

  codesign --force     --keychain "$KEYCHAIN"     --entitlements "$entitlements"     --sign "$IDENTITY"     --timestamp=none     "$APP_PATH"

  codesign --verify --strict "$battery_helper"
  codesign --verify --deep --strict "$APP_PATH"

  local helper_authority
  helper_authority="$(codesign -dv --verbose=4 "$battery_helper" 2>&1 |
    sed -n 's/^Authority=//p' | head -1)"
  [[ "$helper_authority" == "$IDENTITY" ]] ||
    die "unexpected battery helper signing authority: ${helper_authority:-none}"

  local authority
  authority="$(codesign -dv --verbose=4 "$APP_PATH" 2>&1 |
    sed -n 's/^Authority=//p' | head -1)"
  [[ "$authority" == "$IDENTITY" ]] ||
    die "unexpected signing authority: ${authority:-none}"

  echo "CATCLEANER_LOCAL_SIGN_PASS"
  echo "identity=$IDENTITY"
  echo "app=$APP_PATH"
}

case "$MODE" in
  --ensure)
    ensure_identity
    ;;
  --check)
    check_identity
    ;;
  --sign)
    sign_app
    ;;
  *)
    echo "Usage: $0 [--ensure|--check|--sign APP]" >&2
    exit 64
    ;;
esac
