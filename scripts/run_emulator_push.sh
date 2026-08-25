#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v flutter >/dev/null 2>&1; then
  echo "[ERR] flutter not found in PATH" >&2
  exit 1
fi

DEVICE_ID="${1:-${ANDROID_DEVICE_ID:-}}"
if [[ -z "$DEVICE_ID" ]]; then
  DEVICE_ID="$(flutter devices --machine | python3 -c 'import json,sys
try:
    arr=json.load(sys.stdin)
except Exception:
    print("")
    raise SystemExit
for d in arr:
    if d.get("platformType")=="android" and str(d.get("id","")).startswith("emulator-"):
        print(d["id"])
        break
')"
fi

if [[ -z "$DEVICE_ID" ]]; then
  echo "[ERR] No Android emulator found; start one or pass its device ID." >&2
  exit 1
fi

# shellcheck source=scripts/_supabase_client_env.sh
source "${ROOT_DIR}/scripts/_supabase_client_env.sh"
load_supabase_client_env "$ROOT_DIR"
if [[ -z "${SUPABASE_URL:-}" ]]; then
  SUPABASE_URL="http://${ANDROID_EMULATOR_HOST:-10.0.2.2}:${SUPABASE_LOCAL_PORT:-54321}"
fi
require_supabase_client_env "$ROOT_DIR"

echo "[INFO] Starting on the selected Android emulator."

# Gradle cache corruption recovery (NoSuchFileException in transforms cache)
( cd android && ./gradlew --stop ) || true
flutter clean
rm -rf android/.gradle \
  "$HOME/.gradle/caches/transforms-"* \
  "$HOME/.gradle/caches/jars-"* \
  "$HOME/.gradle/caches/"*/plugin-resolution/* || true

flutter pub get
flutter run -d "$DEVICE_ID" \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
  --android-skip-build-dependency-validation
