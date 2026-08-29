import 'dart:async';

import 'package:couple_chat_app/src/features/settings/data/theme_mode_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SharedPreferencesThemeModeStore', () {
    const store = SharedPreferencesThemeModeStore();

    test('저장값이 없거나 손상되면 시스템 모드를 사용한다', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await store.load(), ThemeMode.system);

      SharedPreferences.setMockInitialValues({
        appThemeModePreferenceKey: 'unknown-mode',
      });
      expect(await store.load(), ThemeMode.system);

      SharedPreferences.setMockInitialValues({
        appThemeModePreferenceKey: 7,
      });
      expect(await store.load(), ThemeMode.system);
    });

    test('선택한 화면 모드를 저장하고 다시 읽는다', () async {
      SharedPreferences.setMockInitialValues({});

      await store.save(ThemeMode.dark);

      expect(await store.load(), ThemeMode.dark);
      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getString(appThemeModePreferenceKey),
        'dark',
      );
    });
  });

  group('ThemeModePreferenceController', () {
    test('선택을 즉시 반영하고 저장이 끝나면 busy 상태를 해제한다', () async {
      final store = _ControlledThemeModeStore();
      final container = ProviderContainer(
        overrides: [
          initialThemeModeProvider.overrideWithValue(ThemeMode.system),
          themeModePreferencesStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(container.dispose);

      final save = container
          .read(themeModeControllerProvider.notifier)
          .selectMode(ThemeMode.dark);

      expect(
        container.read(themeModeControllerProvider),
        isA<ThemeModePreferenceState>()
            .having((state) => state.mode, 'mode', ThemeMode.dark)
            .having((state) => state.isSaving, 'isSaving', isTrue),
      );
      expect(store.savedModes, [ThemeMode.dark]);

      store.completeSave();
      expect(await save, isTrue);
      expect(
        container.read(themeModeControllerProvider),
        isA<ThemeModePreferenceState>()
            .having((state) => state.mode, 'mode', ThemeMode.dark)
            .having((state) => state.isSaving, 'isSaving', isFalse)
            .having((state) => state.saveError, 'saveError', isNull),
      );
    });

    test('저장 실패 시 이전 모드로 즉시 롤백한다', () async {
      final store = _FailingThemeModeStore();
      final container = ProviderContainer(
        overrides: [
          initialThemeModeProvider.overrideWithValue(ThemeMode.dark),
          themeModePreferencesStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(container.dispose);

      final didSave = await container
          .read(themeModeControllerProvider.notifier)
          .selectMode(ThemeMode.light);

      expect(didSave, isFalse);
      expect(
        container.read(themeModeControllerProvider),
        isA<ThemeModePreferenceState>()
            .having((state) => state.mode, 'mode', ThemeMode.dark)
            .having((state) => state.isSaving, 'isSaving', isFalse)
            .having((state) => state.saveError, 'saveError', isNotNull),
      );
    });

    test('저장 중 빠른 중복 선택을 막는다', () async {
      final store = _ControlledThemeModeStore();
      final controller = ThemeModePreferenceController(
        store: store,
        initialMode: ThemeMode.system,
      );
      addTearDown(controller.dispose);

      final first = controller.selectMode(ThemeMode.dark);
      final second = await controller.selectMode(ThemeMode.light);

      expect(second, isFalse);
      expect(store.savedModes, [ThemeMode.dark]);
      expect(controller.state.mode, ThemeMode.dark);

      store.completeSave();
      expect(await first, isTrue);
    });
  });
}

class _ControlledThemeModeStore implements ThemeModePreferencesStore {
  final savedModes = <ThemeMode>[];
  Completer<void>? _saveCompleter;

  @override
  Future<ThemeMode> load() async => ThemeMode.system;

  @override
  Future<void> save(ThemeMode mode) {
    savedModes.add(mode);
    _saveCompleter = Completer<void>();
    return _saveCompleter!.future;
  }

  void completeSave() {
    _saveCompleter!.complete();
  }
}

class _FailingThemeModeStore implements ThemeModePreferencesStore {
  @override
  Future<ThemeMode> load() async => ThemeMode.system;

  @override
  Future<void> save(ThemeMode mode) async {
    throw StateError('save failed');
  }
}
