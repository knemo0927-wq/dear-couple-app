#!/usr/bin/env bash
set -euo pipefail

# Run Flutter app on iOS device with Supabase Cloud (release by default)
# Priority:
# 1) Explicit env SUPABASE_URL / SUPABASE_ANON_KEY
# 2) Project-root .env.local (client values only)
# Optional:
# - IOS_DEVICE_ID
# - IOS_TEAM_ID (10-char Apple Developer Team ID, e.g. ABCD123456)
# - BUILD_MODE=release|debug|profile (default: release)

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/_supabase_client_env.sh
source "${ROOT_DIR}/scripts/_supabase_client_env.sh"
load_supabase_client_env "$ROOT_DIR"
require_supabase_client_env "$ROOT_DIR"

if [[ -z "${SUPABASE_URL:-}" || -z "${SUPABASE_ANON_KEY:-}" ]]; then
  echo "Missing SUPABASE_URL/SUPABASE_ANON_KEY." >&2
  echo "Either run with env vars:" >&2
  echo "  SUPABASE_URL=https://<project>.supabase.co SUPABASE_ANON_KEY=<anon> IOS_DEVICE_ID=<optional> $0" >&2
  echo "or add client-only values to ${ROOT_DIR}/.env.local." >&2
  exit 1
fi

cd "$ROOT_DIR"

DEVICE_FLAG=""
if [[ -n "${IOS_DEVICE_ID:-}" ]]; then
  DEVICE_FLAG="-d ${IOS_DEVICE_ID}"
fi

BUILD_MODE="${BUILD_MODE:-release}"
MODE_FLAG="--release"
case "$BUILD_MODE" in
  debug) MODE_FLAG="--debug" ;;
  profile) MODE_FLAG="--profile" ;;
  release) MODE_FLAG="--release" ;;
  *)
    echo "Invalid BUILD_MODE=$BUILD_MODE (allowed: release|debug|profile)" >&2
    exit 1
    ;;
esac

echo "[run_ios_cloud] mode=$BUILD_MODE"

if [[ -n "${IOS_TEAM_ID:-}" ]]; then
  if [[ ! "${IOS_TEAM_ID}" =~ ^[A-Z0-9]{10}$ ]]; then
    echo "Invalid IOS_TEAM_ID. Expected 10-char Team ID (A-Z0-9)." >&2
    exit 1
  fi

  PBXPROJ_PATH="${ROOT_DIR}/ios/Runner.xcodeproj/project.pbxproj"
  if [[ ! -f "${PBXPROJ_PATH}" ]]; then
    echo "Missing Xcode project file: ${PBXPROJ_PATH}" >&2
    exit 1
  fi

  PBXPROJ_BACKUP="$(mktemp -t dear-run-ios-cloud-pbxproj.XXXXXX)"
  cp "$PBXPROJ_PATH" "$PBXPROJ_BACKUP"
  restore_pbxproj() {
    if [[ -f "${PBXPROJ_BACKUP:-}" ]]; then
      cp "$PBXPROJ_BACKUP" "$PBXPROJ_PATH"
      rm -f "$PBXPROJ_BACKUP"
    fi
  }
  trap restore_pbxproj EXIT

  echo "[run_ios_cloud] applying the configured IOS_TEAM_ID"
  python3 - "${PBXPROJ_PATH}" "${IOS_TEAM_ID}" <<'PY'
import re
import sys
from pathlib import Path

pbxproj = Path(sys.argv[1])
team = sys.argv[2]
text = pbxproj.read_text(encoding='utf-8')
new_text, n = re.subn(
    r'DEVELOPMENT_TEAM = (?:""|[A-Z0-9]{10});',
    f"DEVELOPMENT_TEAM = {team};",
    text,
)
if n == 0:
    print("No DEVELOPMENT_TEAM entries found in project.pbxproj", file=sys.stderr)
    sys.exit(1)
pbxproj.write_text(new_text, encoding='utf-8')
print(f"Updated DEVELOPMENT_TEAM entries: {n}")
PY
fi

flutter pub get
# shellcheck disable=SC2086
flutter run ${MODE_FLAG} ${DEVICE_FLAG}   --dart-define=SUPABASE_URL="$SUPABASE_URL"   --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"
