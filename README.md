# Dear

A Flutter app for couples to chat, preserve memories, track anniversaries, and
map trips. It is backed by Supabase, with Firebase configuration for supported
native platforms.

## Local setup

Install Flutter dependencies and create a local environment file:

```sh
flutter pub get
cp .env.example .env.local
```

Fill in the client-safe Supabase values in `.env.local`. The scripts under
`scripts/` load only the two client Supabase values from that file. For a
direct `flutter run`, pass them as Dart defines explicitly:

```sh
set -a
source .env.local
set +a
flutter run \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"
```

The shared script loader deliberately imports only the two Supabase client
values. Export `ANDROID_DEVICE_ID`, `IOS_DEVICE_ID`, `IOS_TEAM_ID`, or
`APPLE_ID` explicitly when a device/signing helper asks for one; several
scripts also accept the device and team IDs as positional arguments.

For Firebase-enabled native builds, copy the relevant sanitized template and
replace every placeholder with the matching values from your own Firebase
project:

```sh
cp android/app/google-services.example.json android/app/google-services.json
cp ios/Runner/GoogleService-Info.example.plist ios/Runner/GoogleService-Info.plist
cp macos/Runner/GoogleService-Info.example.plist macos/Runner/GoogleService-Info.plist
```

The real Firebase configuration filenames are intentionally ignored by Git.

## Security

- `SUPABASE_ANON_KEY` is shipped to clients. Treat it as public and enforce
  access with Supabase Row Level Security policies.
- Never place a Supabase service-role key, an FCM service-account JSON/private
  key, signing credentials, or production secrets in `.env.local`, Dart
  defines, or any client-side source file.
- Keep device IDs, Apple account details, signing files, and generated native
  configuration local. The optional iOS variables in `.env.example` are only
  placeholders for local tooling.
- Ignore rules reduce accidental commits but do not remove data already present
  in Git history. Review staged files before publishing.

Flutter documentation is available at [docs.flutter.dev](https://docs.flutter.dev/).
