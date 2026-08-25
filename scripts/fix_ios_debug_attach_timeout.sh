#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_DIR="$ROOT_DIR/ios"
DEVICE_ID="${1:-${IOS_DEVICE_ID:-}}"

if [[ -z "$DEVICE_ID" ]]; then
  echo "[ERR] iOS device ID is required as argument 1 or IOS_DEVICE_ID." >&2
  exit 1
fi

step(){ echo; echo "===== $1 ====="; }

step "1) Kill stale Xcode debug/build services"
killall Xcode xcodebuild XCBBuildService SourceKitService 2>/dev/null || true

step "2) Clean only build artifacts (keep pods)"
cd "$ROOT_DIR"
flutter clean
flutter pub get

step "3) Launch once from Xcode (required)"
open -a Xcode "$IOS_DIR/Runner.xcworkspace"
cat <<'MSG'
[Xcode에서 직접 1회 실행]
1) Runner 스킴 + 실제 기기 선택
2) Product > Run (Cmd+R) 1회 실행
3) 기기/맥에 뜨는 권한 팝업 모두 허용(Always Allow/Trust)
4) 앱이 기기에서 뜨면 터미널로 돌아와 Enter
MSG
read -r _

step "4) Attach Flutter debugger to running app"
cd "$ROOT_DIR"
flutter attach -d "$DEVICE_ID"
