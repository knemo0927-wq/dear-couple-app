#!/usr/bin/env bash
set -euo pipefail

# Run Flutter app on Android with Supabase Cloud
# Priority:
# 1) Explicit env SUPABASE_URL / SUPABASE_ANON_KEY
# 2) Project-root .env.local (client values only)

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/_supabase_client_env.sh
source "${ROOT_DIR}/scripts/_supabase_client_env.sh"
load_supabase_client_env "$ROOT_DIR"
require_supabase_client_env "$ROOT_DIR"

cd "$ROOT_DIR"
flutter pub get
flutter run   --dart-define=SUPABASE_URL="$SUPABASE_URL"   --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"
