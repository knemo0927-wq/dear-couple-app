class AppConfig {
  const AppConfig({
    required this.supabaseUrl,
    required this.supabaseAnonKey,
  });

  final String supabaseUrl;
  final String supabaseAnonKey;

  bool get hasSupabaseConfig =>
      supabaseUrl.trim().isNotEmpty && supabaseAnonKey.trim().isNotEmpty;

  static const fromEnv = AppConfig(
    supabaseUrl: String.fromEnvironment('SUPABASE_URL', defaultValue: ''),
    supabaseAnonKey:
        String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: ''),
  );
}
