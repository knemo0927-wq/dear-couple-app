#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEYCHAIN="${KEYCHAIN_PATH:-$HOME/Library/Keychains/login.keychain-db}"
DEVICE_ID="${1:-${IOS_DEVICE_ID:-}}"
TEAM_ID="${2:-${IOS_TEAM_ID:-}}"

if [[ -z "$DEVICE_ID" ]]; then
  echo "[ERR] iOS device ID is required as argument 1 or IOS_DEVICE_ID." >&2
  exit 1
fi
if [[ ! "$TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then
  echo "[ERR] IOS_TEAM_ID (or argument 2) must be a 10-character Apple Team ID." >&2
  exit 1
fi

echo "[1/8] Close Xcode"
osascript -e 'tell application "Xcode" to quit' || true
killall Xcode 2>/dev/null || true

echo "[2/8] Remove stale Xcode keychain tokens"
for SVC in Xcode-Token Xcode-Username Xcode-AlternateDSID Xcode-Session; do
  security delete-generic-password -s "$SVC" "$KEYCHAIN" 2>/dev/null || true
done

echo "[3/8] Unlock keychain and refresh codesign ACL"
read -s -p "macOS login password: " LOGIN_PASS; echo
security unlock-keychain -p "$LOGIN_PASS" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
if ! security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$LOGIN_PASS" "$KEYCHAIN"; then
  echo "[warn] set-key-partition-list failed (stale keychain item). Continuing; approve Always Allow on key prompts during build."
fi

echo "[4/8] Verify signing identities"
security find-identity -v -p codesigning | head -n 20

echo "[5/8] Ensure Runner signing config"
PBX="$ROOT_DIR/ios/Runner.xcodeproj/project.pbxproj"
PBX_BACKUP="$(mktemp -t dear-pbxproj-keychain.XXXXXX)"
cp "$PBX" "$PBX_BACKUP"
echo "[INFO] Temporary project backup created outside the repository."
perl -i -pe "s/DEVELOPMENT_TEAM = (?:\"\"|[A-Z0-9]{10});/DEVELOPMENT_TEAM = $TEAM_ID;/g" "$PBX"
perl -i -pe 's/CODE_SIGN_STYLE = Manual;/CODE_SIGN_STYLE = Automatic;/g' "$PBX"
perl -i -pe 's/IPHONEOS_DEPLOYMENT_TARGET = 12\.0;/IPHONEOS_DEPLOYMENT_TARGET = 13.0;/g' "$PBX"

echo "[6/8] Clean and resolve deps"
cd "$ROOT_DIR"
flutter clean
flutter pub get
cd ios
pod install
cd ..

echo "[7/8] Open Xcode workspace for account refresh"
open -a Xcode ios/Runner.xcworkspace
cat <<'MSG'
=== REQUIRED IN Xcode (1 minute) ===
1) Xcode > Settings > Accounts: remove/re-add the intended Apple ID if needed
2) Manage Certificates...: ensure Apple Development cert exists
3) Runner target > Signing & Capabilities:
   - Team: select the team supplied through IOS_TEAM_ID
   - Automatically manage signing: ON
4) If a key prompt appears during build, click Always Allow
=====================================
MSG
read -p "Press Enter after finishing Xcode steps..." _

echo "[8/8] Run on physical device"
flutter run -d "$DEVICE_ID"
