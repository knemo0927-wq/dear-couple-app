import 'package:couple_chat_app/src/app_root.dart';
import 'package:couple_chat_app/src/features/settings/data/theme_mode_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Supabase 설정이 없으면 setup 안내 페이지로 이동한다',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: CoupleChatApp(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Dear'), findsOneWidget);
    expect(find.text('SUPABASE_URL / SUPABASE_ANON_KEY를 dart-define으로 주입하세요'),
        findsOneWidget);
  });

  testWidgets('저장된 화면 모드가 첫 MaterialApp 프레임부터 적용된다',
      (WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        initialThemeModeProvider.overrideWithValue(ThemeMode.dark),
        themeModePreferencesStoreProvider.overrideWithValue(
          _MemoryThemeModeStore(),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const CoupleChatApp(),
      ),
    );

    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark);

    await container
        .read(themeModeControllerProvider.notifier)
        .selectMode(ThemeMode.light);
    await tester.pump();

    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.light);
  });
}

class _MemoryThemeModeStore implements ThemeModePreferencesStore {
  @override
  Future<ThemeMode> load() async => ThemeMode.system;

  @override
  Future<void> save(ThemeMode mode) async {}
}
