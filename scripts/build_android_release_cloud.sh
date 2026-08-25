#!/usr/bin/env bash
set -euo pipefail

# Build Android release artifacts (.aab + .apk) with Supabase Cloud defines.
# Priority:
# 1) Explicit env SUPABASE_URL / SUPABASE_ANON_KEY
# 2) Project-root .env.local (client values only)

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/_supabase_client_env.sh
source "${ROOT_DIR}/scripts/_supabase_client_env.sh"
load_supabase_client_env "$ROOT_DIR"
require_supabase_client_env "$ROOT_DIR"

cd "$ROOT_DIR"
flutter clean
flutter pub get

flutter build appbundle --release \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"

flutter build apk --release \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"

echo "✅ Android release build done"
echo "- AAB: $ROOT_DIR/build/app/outputs/bundle/release/app-release.aab"
echo "- APK: $ROOT_DIR/build/app/outputs/flutter-apk/app-release.apk"
