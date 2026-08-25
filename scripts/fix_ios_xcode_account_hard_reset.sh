#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEYCHAIN="${KEYCHAIN_PATH:-$HOME/Library/Keychains/login.keychain-db}"
DEVICE_ID="${1:-${IOS_DEVICE_ID:-}}"
TEAM_ID="${2:-${IOS_TEAM_ID:-}}"
APPLE_ID="${APPLE_ID:-}"

if [[ -z "$DEVICE_ID" ]]; then
  echo "[ERR] iOS device ID is required as argument 1 or IOS_DEVICE_ID." >&2
  exit 1
fi
if [[ ! "$TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then
  echo "[ERR] IOS_TEAM_ID (or argument 2) must be a 10-character Apple Team ID." >&2
  exit 1
fi
if [[ -z "$APPLE_ID" || "$APPLE_ID" != *@* ]]; then
  echo "[ERR] APPLE_ID must be set to the Xcode account email." >&2
  exit 1
fi

echo "[1/10] Quit Xcode"
osascript -e 'tell application "Xcode" to quit' || true
killall Xcode 2>/dev/null || true

echo "[2/10] Purge broken Xcode account cache/tokens"
rm -rf "$HOME/Library/Developer/Xcode/UserData/Accounts" || true
rm -rf "$HOME/Library/Caches/com.apple.dt.Xcode" || true
for SVC in Xcode-Token Xcode-Username Xcode-AlternateDSID Xcode-Session; do
  security delete-generic-password -s "$SVC" "$KEYCHAIN" 2>/dev/null || true
done

echo "[3/10] Unlock keychain"
read -s -p "macOS login password: " LOGIN_PASS; echo
security unlock-keychain -p "$LOGIN_PASS" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security list-keychains -d user -s "$KEYCHAIN"
security default-keychain -d user -s "$KEYCHAIN"

echo "[4/10] Ensure pbxproj signing/deployment settings"
PBX="$ROOT_DIR/ios/Runner.xcodeproj/project.pbxproj"
PBX_BACKUP="$(mktemp -t dear-pbxproj-account.XXXXXX)"
cp "$PBX" "$PBX_BACKUP"
echo "[INFO] Temporary project backup created outside the repository."
perl -i -pe "s/DEVELOPMENT_TEAM = (?:\"\"|[A-Z0-9]{10});/DEVELOPMENT_TEAM = $TEAM_ID;/g" "$PBX"
perl -i -pe 's/CODE_SIGN_STYLE = Manual;/CODE_SIGN_STYLE = Automatic;/g' "$PBX"
perl -i -pe 's/IPHONEOS_DEPLOYMENT_TARGET = 12\.0;/IPHONEOS_DEPLOYMENT_TARGET = 13.0;/g' "$PBX"

echo "[5/10] Recreate deps/build cache"
rm -rf "$HOME/Library/Developer/Xcode/DerivedData"/* || true
cd "$ROOT_DIR"
flutter clean
flutter pub get
(cd ios && pod install)

echo "[6/10] Open Xcode workspace for full account/cert re-creation"
open -a Xcode ios/Runner.xcworkspace
cat <<'MSG'
=== REQUIRED IN Xcode (MUST DO EXACTLY) ===
A) Xcode > Settings > Accounts:
   1. Remove ALL Apple IDs shown there.
   2. Close Settings window.
   3. Open Settings > Accounts again and add only the account supplied via APPLE_ID.
B) Select the added account > Manage Certificates...
   1. Delete existing Apple Development certs (if duplicated/broken).
   2. Press + and create ONE new Apple Development certificate.
C) Runner target > Signing & Capabilities:
   - Team: select the team supplied via IOS_TEAM_ID
   - Automatically manage signing: ON
D) Product > Clean Build Folder (Shift+Cmd+K)
=========================================
MSG
read -p "Press Enter AFTER finishing A~D in Xcode: " _

echo "[7/10] Verify signing identity exists"
security find-identity -v -p codesigning | sed -n '1,20p'
IDENTITY_HASH=$(security find-identity -v -p codesigning | awk '/Apple Development/{print $2; exit}')
if [[ -z "${IDENTITY_HASH:-}" ]]; then
  echo "❌ No Apple Development identity found in keychain."
  exit 1
fi
echo "Using a discovered Apple Development identity."

echo "[8/10] Refresh key ACL for codesign"
if ! security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$LOGIN_PASS" "$KEYCHAIN"; then
  echo "[warn] set-key-partition-list failed; continuing"
fi

echo "[9/10] Preflight codesign test"
cp /usr/bin/true /tmp/hermes_codesign_test_bin
codesign -f -s "$IDENTITY_HASH" /tmp/hermes_codesign_test_bin
codesign -dv /tmp/hermes_codesign_test_bin 2>&1 | sed -n '1,8p'

echo "[10/10] Flutter run on device"
cd "$ROOT_DIR"
flutter run -d "$DEVICE_ID"
