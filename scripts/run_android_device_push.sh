#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   bash scripts/run_android_device_push.sh <device-id>
#   ANDROID_DEVICE_ID=<device-id> bash scripts/run_android_device_push.sh

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVICE_ID="${1:-${ANDROID_DEVICE_ID:-}}"

if [[ -z "$DEVICE_ID" ]]; then
  echo "[ERR] Android device ID is required as argument 1 or ANDROID_DEVICE_ID." >&2
  exit 1
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "[ERR] flutter not found in PATH" >&2
  exit 1
fi

# shellcheck source=scripts/_supabase_client_env.sh
source "${ROOT_DIR}/scripts/_supabase_client_env.sh"
load_supabase_client_env "$ROOT_DIR"

# A physical Android device needs the Mac LAN address for a local Supabase
# instance. Explicit env/.env.local settings take priority over this fallback.
if [[ -z "${SUPABASE_URL:-}" ]]; then
  MAC_IP="$(ipconfig getifaddr en0 2>/dev/null || true)"
  if [[ -z "$MAC_IP" ]]; then
    MAC_IP="$(ipconfig getifaddr en1 2>/dev/null || true)"
  fi
  if [[ -z "$MAC_IP" ]]; then
    echo "[ERR] Could not detect a Mac LAN IP; set SUPABASE_URL explicitly." >&2
    exit 1
  fi
  SUPABASE_URL="http://${MAC_IP}:${SUPABASE_LOCAL_PORT:-54321}"
fi

require_supabase_client_env "$ROOT_DIR"

cd "$ROOT_DIR"
flutter doctor --android-licenses || true
flutter pub get
flutter devices
flutter run -d "$DEVICE_ID" \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"
