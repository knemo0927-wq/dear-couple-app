import 'package:couple_chat_app/src/app_root.dart';
import 'package:couple_chat_app/src/config/app_config.dart';
import 'package:couple_chat_app/src/features/notifications/data/push_registration_providers.dart';
import 'package:couple_chat_app/src/features/settings/data/theme_mode_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  ThemeMode initialThemeMode;
  try {
    initialThemeMode = await const SharedPreferencesThemeModeStore().load();
  } catch (_) {
    initialThemeMode = ThemeMode.system;
  }

  const config = AppConfig.fromEnv;
  if (config.hasSupabaseConfig) {
    await Supabase.initialize(
      url: config.supabaseUrl,
      anonKey: config.supabaseAnonKey,
    );
  }

  // Firebase config file이 없는 환경(로컬/CI)에서도 앱 부팅은 진행되도록 보호.
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // ignore
  }

  runApp(
    ProviderScope(
      overrides: [
        initialThemeModeProvider.overrideWithValue(initialThemeMode),
      ],
      child: const PushRegistrationSync(
        child: CoupleChatApp(),
      ),
    ),
  );
}
