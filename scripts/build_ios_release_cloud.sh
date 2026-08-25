#!/usr/bin/env bash
set -euo pipefail

# Build iOS release ipa with Supabase Cloud defines.
# Requires macOS + Xcode + CocoaPods + signing configured.
# Priority:
# 1) Explicit env SUPABASE_URL / SUPABASE_ANON_KEY
# 2) Project-root .env.local (client values only)
#
# Optional:
# - IOS_EXPORT_METHOD=development|ad-hoc|enterprise|app-store (default: development)
# - EXPORT_PLIST_PATH=/absolute/path/to/ExportOptions.plist

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_EXPORT_METHOD="${IOS_EXPORT_METHOD:-development}"
EXPORT_PLIST_PATH="${EXPORT_PLIST_PATH:-$ROOT_DIR/ios/ExportOptions.$IOS_EXPORT_METHOD.plist}"

# shellcheck source=scripts/_supabase_client_env.sh
source "${ROOT_DIR}/scripts/_supabase_client_env.sh"
load_supabase_client_env "$ROOT_DIR"
require_supabase_client_env "$ROOT_DIR"

# Auto-generate ExportOptions.plist if missing.
if [[ ! -f "$EXPORT_PLIST_PATH" ]]; then
  cat > "$EXPORT_PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>${IOS_EXPORT_METHOD}</string>
  <key>signingStyle</key><string>automatic</string>
  <key>stripSwiftSymbols</key><true/>
  <key>uploadSymbols</key><true/>
  <key>compileBitcode</key><false/>
</dict>
</plist>
PLIST
fi

cd "$ROOT_DIR"
flutter clean
flutter pub get
cd ios
pod install
cd ..

echo "[build_ios_release_cloud] export_method=${IOS_EXPORT_METHOD}"
echo "[build_ios_release_cloud] export_plist=${EXPORT_PLIST_PATH}"

flutter build ipa --release \
  --export-options-plist="$EXPORT_PLIST_PATH" \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"

shopt -s nullglob
ipas=("$ROOT_DIR"/build/ios/ipa/*.ipa)
if (( ${#ipas[@]} == 0 )); then
  echo "❌ IPA export failed: no .ipa file produced." >&2
  echo "Hint: Personal Team 계정은 app-store export가 막힐 수 있음. IOS_EXPORT_METHOD=development 로 다시 시도." >&2
  exit 1
fi

echo "✅ iOS release build done"
for ipa in "${ipas[@]}"; do
  echo "- IPA: $ipa"
done
