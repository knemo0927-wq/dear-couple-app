#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   IOS_DEVICE_ID=<device-id> bash scripts/run_ios_device_push.sh
#   bash scripts/run_ios_device_push.sh <device-id>

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVICE_ID="${1:-${IOS_DEVICE_ID:-}}"

if [[ -z "$DEVICE_ID" ]]; then
  echo "[ERR] iOS device ID is required as argument 1 or IOS_DEVICE_ID." >&2
  exit 1
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "[ERR] flutter not found in PATH" >&2
  exit 1
fi

# shellcheck source=scripts/_supabase_client_env.sh
source "${ROOT_DIR}/scripts/_supabase_client_env.sh"
load_supabase_client_env "$ROOT_DIR"

# A physical iPhone cannot reach the Mac through loopback. If no URL was
# provided, derive a local Supabase endpoint from the active Mac LAN address.
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

echo "[INFO] Starting on the selected iOS device."
cd "$ROOT_DIR"
flutter run -d "$DEVICE_ID" \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"
