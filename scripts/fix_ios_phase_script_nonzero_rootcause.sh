#!/usr/bin/env bash
set -euo pipefail

# Root-cause-targeted fix for PhaseScriptExecution, Xcode account token, and
# codesign errSecInternalComponent failures.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_DIR="$ROOT_DIR/ios"
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

step(){ echo; echo "===== $1 ====="; }

step "1) Stop Xcode"
osascript -e 'tell application "Xcode" to quit' || true
killall Xcode 2>/dev/null || true

step "2) Purge corrupted Xcode account artifacts"
rm -rf "$HOME/Library/Developer/Xcode/UserData/Accounts" || true
rm -rf "$HOME/Library/Caches/com.apple.dt.Xcode" || true
for SVC in Xcode-Token Xcode-Username Xcode-AlternateDSID Xcode-Session; do
  security delete-generic-password -s "$SVC" "$KEYCHAIN" 2>/dev/null || true
  security delete-generic-password -s "$SVC" -a "$APPLE_ID" "$KEYCHAIN" 2>/dev/null || true
done

step "3) Unlock and prioritize login keychain"
read -s -p "macOS login password: " LOGIN_PASS; echo
security unlock-keychain -p "$LOGIN_PASS" "$KEYCHAIN"
security default-keychain -d user -s "$KEYCHAIN"
security list-keychains -d user -s "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"

step "4) Ensure iOS project signing settings"
PBX="$IOS_DIR/Runner.xcodeproj/project.pbxproj"
PBX_BACKUP="$(mktemp -t dear-pbxproj-phase.XXXXXX)"
cp "$PBX" "$PBX_BACKUP"
echo "[INFO] Temporary project backup created outside the repository."
perl -i -pe "s/DEVELOPMENT_TEAM = (?:\"\"|[A-Z0-9]{10});/DEVELOPMENT_TEAM = $TEAM_ID;/g" "$PBX"
perl -i -pe 's/CODE_SIGN_STYLE = Manual;/CODE_SIGN_STYLE = Automatic;/g' "$PBX"
perl -i -pe 's/IPHONEOS_DEPLOYMENT_TARGET = 12\.0;/IPHONEOS_DEPLOYMENT_TARGET = 13.0;/g' "$PBX"

step "5) Rebuild deps"
rm -rf "$HOME/Library/Developer/Xcode/DerivedData"/* || true
cd "$ROOT_DIR"
flutter clean
flutter pub get
(cd ios && pod install)

step "6) Xcode mandatory re-auth + cert recreation"
open -a Xcode "$IOS_DIR/Runner.xcworkspace"
cat <<'MSG'
[필수 수동 작업 - 정확히 수행]
A. Xcode > Settings > Accounts
   - 기존 Apple ID 전부 제거
   - APPLE_ID로 전달한 계정만 다시 추가
B. 해당 계정 > Manage Certificates...
   - Apple Development 인증서가 여러 개면 정리
   - 없거나 의심되면 + 로 새 Apple Development 1개 생성
C. Runner > Signing & Capabilities
   - Team: IOS_TEAM_ID로 전달한 팀 선택
   - Automatically manage signing: ON
D. Product > Clean Build Folder
작업 완료 후 터미널로 돌아와 Enter
MSG
read -r _

step "7) Verify usable signing identity"
security find-identity -v -p codesigning | sed -n '1,30p'
IDENTITY_HASH=$(security find-identity -v -p codesigning | awk '/Apple Development/{print $2; exit}')
if [[ -z "${IDENTITY_HASH:-}" ]]; then
  echo "❌ Apple Development identity not found."
  exit 1
fi
echo "Using a discovered Apple Development identity."

step "8) Repair key ACL for codesign"
if ! security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$LOGIN_PASS" "$KEYCHAIN"; then
  echo "[warn] set-key-partition-list failed; continue with GUI prompt approval"
fi

step "9) Preflight codesign self-test"
cp /usr/bin/true /tmp/hermes_codesign_probe
codesign -f -s "$IDENTITY_HASH" /tmp/hermes_codesign_probe
codesign -dv /tmp/hermes_codesign_probe 2>&1 | sed -n '1,12p'

step "10) Run app"
cd "$ROOT_DIR"
flutter run -d "$DEVICE_ID"
