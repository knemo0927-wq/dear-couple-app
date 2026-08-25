#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_DIR="$ROOT_DIR/ios"
DEVICE_ID="${1:-${IOS_DEVICE_ID:-}}"

if [[ -z "$DEVICE_ID" ]]; then
  echo "[ERR] iOS device ID is required as argument 1 or IOS_DEVICE_ID." >&2
  exit 1
fi

echo "[1/6] Kill Xcode build services"
killall Xcode xcodebuild XCBBuildService SourceKitService 2>/dev/null || true

cd "$IOS_DIR"

echo "[2/6] Quick sync: pod install"
pod install

echo "[3/6] Verify lock sync"
if ! diff -q Podfile.lock Pods/Manifest.lock >/dev/null; then
  echo "[warn] lock mismatch remains -> hard reset pods"
  echo "[4/6] pod deintegrate + reinstall"
  pod deintegrate
  rm -rf Pods Podfile.lock Runner.xcworkspace
  pod repo update
  pod install
fi

echo "[5/6] Final lock check"
diff -q Podfile.lock Pods/Manifest.lock >/dev/null

echo "[6/6] Back to app and run"
cd "$ROOT_DIR"
flutter pub get
flutter run -d "$DEVICE_ID"
