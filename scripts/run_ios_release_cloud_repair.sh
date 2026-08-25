#!/usr/bin/env bash
set -euo pipefail

# One-shot iOS release runner with uninstall/reinstall + verbose log
# Env priority:
# 1) explicit SUPABASE_URL / SUPABASE_ANON_KEY
# 2) Project-root .env.local (client values only)

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/_supabase_client_env.sh
source "${ROOT_DIR}/scripts/_supabase_client_env.sh"
load_supabase_client_env "$ROOT_DIR"
require_supabase_client_env "$ROOT_DIR"

cd "$ROOT_DIR"

BUNDLE_ID="com.nemo.ourmoment"
LOG_PATH="/tmp/flutter_ios_release_verbose.log"

IOS_DEVICE_ID="${IOS_DEVICE_ID:-}"
if [[ -z "$IOS_DEVICE_ID" ]]; then
  IOS_DEVICE_ID="$(flutter devices --machine | python3 -c '
import json
import sys

try:
    devices = json.load(sys.stdin)
except Exception:
    print("")
    raise SystemExit

for device in devices:
    if str(device.get("targetPlatform", "")).startswith("ios") and not bool(device.get("emulator", False)):
        print(device.get("id", ""))
        break
')"
fi

if [[ -z "$IOS_DEVICE_ID" ]]; then
  echo "[ERROR] iOS device not found" >&2
  exit 1
fi

echo "[INFO] An iOS device was selected."

echo "[1/4] flutter clean"
flutter clean

echo "[2/4] flutter pub get"
flutter pub get

echo "[3/4] uninstall old app (ignore failure)"
xcrun devicectl device uninstall app --device "$IOS_DEVICE_ID" "$BUNDLE_ID" || true

echo "[4/4] flutter run --release"
set +e
flutter run --release -d "$IOS_DEVICE_ID" -v   --dart-define=SUPABASE_URL="$SUPABASE_URL"   --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"   2>&1 | tee "$LOG_PATH"
status=${PIPESTATUS[0]}
set -e

echo "[DONE] exit=$status log=$LOG_PATH"
exit $status
