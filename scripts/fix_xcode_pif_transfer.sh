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

step "1) Stop Xcode + related build services"
killall Xcode 2>/dev/null || true
killall xcodebuild 2>/dev/null || true
killall XCBBuildService 2>/dev/null || true
killall SourceKitService 2>/dev/null || true
killall -9 com.apple.CoreSimulator.CoreSimulatorService 2>/dev/null || true

step "2) Remove stale PIF/build state caches"
rm -rf "$HOME/Library/Developer/Xcode/DerivedData"/* || true
rm -rf "$HOME/Library/Caches/org.swift.swiftpm" || true
rm -rf "$HOME/Library/Developer/Xcode/SourcePackages" || true
rm -rf "$HOME/Library/Caches/com.apple.dt.Xcode" || true

step "3) Reset Flutter/iOS generated state"
cd "$ROOT_DIR"
flutter clean
flutter pub get
cd "$IOS_DIR"
pod deintegrate
rm -rf Pods Podfile.lock Runner.xcworkspace
pod install
cd "$ROOT_DIR"

step "4) Open workspace once and let Xcode stabilize"
open -a Xcode "$IOS_DIR/Runner.xcworkspace"
echo "Xcode 열리면 20~30초 대기 후 다시 닫아도 됩니다."
read -p "준비되면 Enter: " _

step "5) Retry run on device"
cd "$ROOT_DIR"
flutter run -d "$DEVICE_ID"
