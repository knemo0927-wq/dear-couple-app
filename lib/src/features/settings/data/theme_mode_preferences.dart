import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const appThemeModePreferenceKey = 'app_theme_mode_v1';

ThemeMode themeModeFromPreference(String? value) {
  return switch (value) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
}

String themeModePreferenceValue(ThemeMode mode) {
  return switch (mode) {
    ThemeMode.system => 'system',
    ThemeMode.light => 'light',
    ThemeMode.dark => 'dark',
  };
}

String themeModeLabel(ThemeMode mode) {
  return switch (mode) {
    ThemeMode.system => '시스템 설정에 맞춤',
    ThemeMode.light => '라이트',
    ThemeMode.dark => '다크',
  };
}

abstract interface class ThemeModePreferencesStore {
  Future<ThemeMode> load();

  Future<void> save(ThemeMode mode);
}

class SharedPreferencesThemeModeStore implements ThemeModePreferencesStore {
  const SharedPreferencesThemeModeStore();

  @override
  Future<ThemeMode> load() async {
    final preferences = await SharedPreferences.getInstance();
    final value = preferences.get(appThemeModePreferenceKey);
    return themeModeFromPreference(value is String ? value : null);
  }

  @override
  Future<void> save(ThemeMode mode) async {
    final preferences = await SharedPreferences.getInstance();
    final didSave = await preferences.setString(
      appThemeModePreferenceKey,
      themeModePreferenceValue(mode),
    );
    if (!didSave) {
      throw StateError('화면 모드 설정을 저장하지 못했습니다.');
    }
  }
}

@immutable
class ThemeModePreferenceState {
  const ThemeModePreferenceState({
    required this.mode,
    this.isSaving = false,
    this.saveError,
  });

  final ThemeMode mode;
  final bool isSaving;
  final Object? saveError;
}

final initialThemeModeProvider = Provider<ThemeMode>(
  (ref) => ThemeMode.system,
);

final themeModePreferencesStoreProvider = Provider<ThemeModePreferencesStore>(
  (ref) => const SharedPreferencesThemeModeStore(),
);

final themeModeControllerProvider = StateNotifierProvider<
    ThemeModePreferenceController, ThemeModePreferenceState>((ref) {
  return ThemeModePreferenceController(
    store: ref.watch(themeModePreferencesStoreProvider),
    initialMode: ref.watch(initialThemeModeProvider),
  );
});

class ThemeModePreferenceController
    extends StateNotifier<ThemeModePreferenceState> {
  ThemeModePreferenceController({
    required ThemeModePreferencesStore store,
    required ThemeMode initialMode,
  })  : _store = store,
        super(ThemeModePreferenceState(mode: initialMode));

  final ThemeModePreferencesStore _store;

  Future<bool> selectMode(ThemeMode mode) async {
    if (state.isSaving) return false;
    if (state.mode == mode) return true;

    final previousMode = state.mode;
    state = ThemeModePreferenceState(mode: mode, isSaving: true);
    try {
      await _store.save(mode);
      state = ThemeModePreferenceState(mode: mode);
      return true;
    } catch (error) {
      state = ThemeModePreferenceState(
        mode: previousMode,
        saveError: error,
      );
      return false;
    }
  }

  void clearSaveError() {
    if (state.saveError == null) return;
    state = ThemeModePreferenceState(
      mode: state.mode,
      isSaving: state.isSaving,
    );
  }
}
