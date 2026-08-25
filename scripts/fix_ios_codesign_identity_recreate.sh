#!/usr/bin/env bash
set -euo pipefail

# Fix errSecInternalComponent when codesigning even simple binaries.
# Root cause: broken Apple Development cert/private-key pair in login keychain.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_DIR="$ROOT_DIR/ios"
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

step(){ echo; echo "===== $1 ====="; }

step "1) Quit Xcode"
osascript -e 'tell application "Xcode" to quit' || true
killall Xcode 2>/dev/null || true

step "2) Unlock login keychain"
read -s -p "macOS login password: " LOGIN_PASS; echo
security unlock-keychain -p "$LOGIN_PASS" "$KEYCHAIN"
security default-keychain -d user -s "$KEYCHAIN"
security list-keychains -d user -s "$KEYCHAIN"

step "3) Delete ALL Apple Development certs from login keychain"
while read -r SHA; do
  [[ -n "$SHA" ]] || continue
  echo "- deleting one stale certificate"
  security delete-certificate -Z "$SHA" "$KEYCHAIN" || true
done < <(security find-certificate -a -Z -c "Apple Development" "$KEYCHAIN" 2>/dev/null | awk '/SHA-1 hash:/{print $3}')

step "4) Clear Xcode account cache"
rm -rf "$HOME/Library/Developer/Xcode/UserData/Accounts" || true
rm -rf "$HOME/Library/Caches/com.apple.dt.Xcode" || true
for SVC in Xcode-Token Xcode-Username Xcode-AlternateDSID Xcode-Session; do
  security delete-generic-password -s "$SVC" "$KEYCHAIN" 2>/dev/null || true
done

step "5) Reopen Xcode and recreate ONE Apple Development cert"
open -a Xcode "$IOS_DIR/Runner.xcworkspace"
cat <<'MSG'
[필수]
A) Xcode > Settings > Accounts: 사용할 Apple ID로 다시 로그인
B) Manage Certificates...:
   - Apple Development 인증서가 있으면 모두 삭제
   - + 눌러 Apple Development 1개 새로 생성
C) Runner > Signing & Capabilities:
   - Team: IOS_TEAM_ID로 전달한 팀 선택
   - Automatically manage signing: ON
D) Product > Clean Build Folder
작업 후 Enter
MSG
read -r _

step "6) Verify identity + preflight codesign"
security find-identity -v -p codesigning | sed -n '1,30p'
IDENTITY_HASH=$(security find-identity -v -p codesigning | awk '/Apple Development/{print $2; exit}')
if [[ -z "${IDENTITY_HASH:-}" ]]; then
  echo "❌ Apple Development identity 없음"
  exit 1
fi

echo "Using a discovered Apple Development identity."
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$LOGIN_PASS" "$KEYCHAIN" || true
cp /usr/bin/true /tmp/hermes_codesign_probe
codesign -f -s "$IDENTITY_HASH" /tmp/hermes_codesign_probe
codesign -dv /tmp/hermes_codesign_probe 2>&1 | sed -n '1,12p'

echo "✅ Preflight codesign success"

step "7) Rebuild and run"
cd "$ROOT_DIR"
flutter clean
flutter pub get
(cd ios && pod install)
flutter run -d "$DEVICE_ID"
