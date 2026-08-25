#!/usr/bin/env bash
set -euo pipefail

# One-shot iOS release runner for a connected device.
#
# Env priority:
# 1) Explicit SUPABASE_URL / SUPABASE_ANON_KEY
# 2) Project-root .env.local (client values only)
#
# Optional:
# - IOS_DEVICE_ID=<device id>          # defaults to the first connected iOS device
# - IOS_TEAM_ID=<10-char team id>      # temporarily writes DEVELOPMENT_TEAM
# - UNINSTALL_FIRST=1                  # remove old app before install (clears app data)
# - FLUTTER_CLEAN=1                    # run flutter clean before release run
# - VERBOSE=1                          # use flutter -v and tee logs

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_LOCAL_FILE="${ROOT_DIR}/.env.local"
LOG_PATH="${LOG_PATH:-/tmp/dear_ios_release_now.log}"

# shellcheck source=scripts/_supabase_client_env.sh
source "${ROOT_DIR}/scripts/_supabase_client_env.sh"
load_supabase_client_env "$ROOT_DIR"
require_supabase_client_env "$ROOT_DIR"

if [[ -z "${SUPABASE_URL:-}" || -z "${SUPABASE_ANON_KEY:-}" ]]; then
  echo "[ERROR] Missing SUPABASE_URL/SUPABASE_ANON_KEY." >&2
  echo "Use:" >&2
  echo "  SUPABASE_URL=https://<project>.supabase.co SUPABASE_ANON_KEY=<anon> ./scripts/run_ios_release_now.sh" >&2
  echo "or add client-only values to: $ENV_LOCAL_FILE" >&2
  exit 1
fi

cd "$ROOT_DIR"

if [[ -z "${IOS_DEVICE_ID:-}" ]]; then
  echo "[run_ios_release_now] selecting first directly connected iOS device..."
  IOS_DEVICE_ID="$(
    flutter devices | python3 -c '
import sys

in_wireless_section = False
selected = ""
for raw_line in sys.stdin.read().splitlines():
    line = raw_line.strip()
    if line.startswith("Checking for wireless devices"):
        in_wireless_section = True
        continue
    if in_wireless_section:
        continue
    if "• ios" not in line or "•" not in line:
        continue
    parts = [part.strip() for part in line.split("•")]
    if len(parts) >= 3 and parts[2] == "ios":
        selected = parts[1]
        break

print(selected)
'
  )"
fi

if [[ -z "${IOS_DEVICE_ID:-}" ]]; then
  echo "[run_ios_release_now] no directly connected iOS device found; falling back to first iOS device from Flutter."
  IOS_DEVICE_ID="$(
    flutter devices --machine | python3 -c '
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
'
  )"
fi

if [[ -z "${IOS_DEVICE_ID:-}" ]]; then
  echo "[ERROR] No connected iOS device found. Set IOS_DEVICE_ID manually." >&2
  echo "Available devices:" >&2
  flutter devices >&2 || true
  exit 1
fi

BUNDLE_ID="${IOS_BUNDLE_ID:-$(
  python3 - "$ROOT_DIR/ios/Runner.xcodeproj/project.pbxproj" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
match = re.search(r"PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);", text)
print(match.group(1) if match else "")
PY
)}"

echo "[run_ios_release_now] an iOS device was selected"
echo "[run_ios_release_now] bundle_id=${BUNDLE_ID:-unknown}"
echo "[run_ios_release_now] log=$LOG_PATH"

if [[ -n "${IOS_TEAM_ID:-}" ]]; then
  if [[ ! "${IOS_TEAM_ID}" =~ ^[A-Z0-9]{10}$ ]]; then
    echo "[ERROR] Invalid IOS_TEAM_ID. Expected 10 chars (A-Z0-9)." >&2
    exit 1
  fi

  PBXPROJ_PATH="${ROOT_DIR}/ios/Runner.xcodeproj/project.pbxproj"
  if [[ ! -f "$PBXPROJ_PATH" ]]; then
    echo "[ERROR] Missing Xcode project file: $PBXPROJ_PATH" >&2
    exit 1
  fi

  PBXPROJ_BACKUP="$(mktemp -t dear-run-ios-release-pbxproj.XXXXXX)"
  cp "$PBXPROJ_PATH" "$PBXPROJ_BACKUP"
  restore_pbxproj() {
    if [[ -f "${PBXPROJ_BACKUP:-}" ]]; then
      cp "$PBXPROJ_BACKUP" "$PBXPROJ_PATH"
      rm -f "$PBXPROJ_BACKUP"
    fi
  }
  trap restore_pbxproj EXIT

  echo "[run_ios_release_now] applying the configured IOS_TEAM_ID"
  python3 - "$PBXPROJ_PATH" "$IOS_TEAM_ID" <<'PY'
import re
import sys
from pathlib import Path

pbxproj = Path(sys.argv[1])
team = sys.argv[2]
text = pbxproj.read_text(encoding="utf-8")
new_text, count = re.subn(
    r'DEVELOPMENT_TEAM = (?:""|[A-Z0-9]{10});',
    f"DEVELOPMENT_TEAM = {team};",
    text,
)
if count == 0:
    print("No DEVELOPMENT_TEAM entries found", file=sys.stderr)
    raise SystemExit(1)
pbxproj.write_text(new_text, encoding="utf-8")
print(f"Updated DEVELOPMENT_TEAM entries: {count}")
PY
fi

if [[ "${FLUTTER_CLEAN:-0}" == "1" ]]; then
  echo "[run_ios_release_now] flutter clean"
  flutter clean
fi

echo "[run_ios_release_now] flutter pub get"
flutter pub get

if [[ "${UNINSTALL_FIRST:-0}" == "1" ]]; then
  if [[ -z "$BUNDLE_ID" ]]; then
    echo "[ERROR] Could not detect iOS bundle id for uninstall. Set IOS_BUNDLE_ID." >&2
    exit 1
  fi
  echo "[run_ios_release_now] uninstalling old app: $BUNDLE_ID"
  xcrun devicectl device uninstall app --device "$IOS_DEVICE_ID" "$BUNDLE_ID" || true
fi

echo "[run_ios_release_now] flutter run --release"
cmd=(flutter)
if [[ "${VERBOSE:-0}" == "1" ]]; then
  cmd+=(-v)
fi
cmd+=(
  run
  --release
  -d "$IOS_DEVICE_ID"
  --dart-define=SUPABASE_URL="$SUPABASE_URL"
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"
)

set +e
"${cmd[@]}" 2>&1 | tee "$LOG_PATH"
status=${PIPESTATUS[0]}
set -e

echo "[run_ios_release_now] exit=$status"
exit "$status"
