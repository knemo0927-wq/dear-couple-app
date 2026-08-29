import 'package:couple_chat_app/src/common/app_theme.dart';
import 'package:couple_chat_app/src/features/auth/data/auth_providers.dart';
import 'package:couple_chat_app/src/features/auth/data/auth_repository.dart';
import 'package:couple_chat_app/src/features/settings/data/theme_mode_preferences.dart';
import 'package:couple_chat_app/src/features/settings/presentation/profile_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  const profile = ProfileInfo(
    userId: 'user-1',
    nickname: '긴 닉네임도 잘 보이는 우리',
    pairingCode: 'ABCD',
    coupleId: '11111111-1111-4111-8111-111111111111',
    avatarPath: null,
  );

  late GoRouter router;

  setUp(() {
    router = GoRouter(
      initialLocation: '/profile',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: Text('pairing-destination')),
        ),
        GoRoute(
          path: '/profile',
          builder: (_, __) => const ProfileSettingsPage(),
        ),
        GoRoute(
          path: '/profile/edit',
          builder: (_, __) => const Scaffold(body: Text('profile-edit-detail')),
        ),
        GoRoute(
          path: '/notifications',
          builder: (_, __) => const Scaffold(body: Text('notification-detail')),
        ),
        GoRoute(
          path: '/anniversary-reminders',
          builder: (_, __) => const Scaffold(body: Text('anniversary-detail')),
        ),
        GoRoute(
          path: '/travel-map',
          builder: (_, __) => const Scaffold(body: Text('korea-map-detail')),
        ),
        GoRoute(
          path: '/world-map',
          builder: (_, __) => const Scaffold(body: Text('world-map-detail')),
        ),
        GoRoute(
          path: '/mini-games',
          builder: (_, __) => const Scaffold(body: Text('omok-detail')),
        ),
        GoRoute(
          path: '/auth',
          builder: (_, __) => const Scaffold(body: Text('auth-destination')),
        ),
      ],
    );
    addTearDown(router.dispose);
  });

  Future<void> pumpMore(
    WidgetTester tester, {
    List<Override> overrides = const [],
    double textScale = 1,
    Size size = const Size(390, 844),
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myProfileProvider.overrideWith((ref) async => profile),
          myAvatarUrlProvider.overrideWith((ref) async => null),
          myAccountEmailProvider.overrideWithValue('dear@example.com'),
          ...overrides,
        ],
        child: MaterialApp.router(
          theme: theme,
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
            ),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('더보기 허브가 화면 모드와 명세 섹션을 표시한다', (tester) async {
    await pumpMore(tester);

    expect(find.text('더보기'), findsOneWidget);
    expect(find.text('우리의 기능'), findsOneWidget);
    expect(find.text('알림과 화면'), findsOneWidget);
    expect(find.text('화면 모드'), findsOneWidget);
    expect(find.text('시스템 설정에 맞춤'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('more-delete-account')),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('계정'), findsOneWidget);
    expect(find.text('위험 작업'), findsOneWidget);
    expect(find.text('로그아웃'), findsOneWidget);
    expect(find.text('커플 연결 해제'), findsOneWidget);
    expect(find.text('계정 삭제'), findsOneWidget);
  });

  testWidgets('화면 모드를 선택하면 즉시 반영하고 저장한다', (tester) async {
    final store = _RecordingThemeModeStore();
    await pumpMore(
      tester,
      overrides: [
        themeModePreferencesStoreProvider.overrideWithValue(store),
      ],
    );

    await tester.tap(find.byKey(const ValueKey('more-theme-mode')));
    await tester.pumpAndSettle();

    expect(find.text('시스템 설정에 맞춤'), findsWidgets);
    expect(find.text('라이트'), findsOneWidget);
    expect(find.text('다크'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('theme-mode-dark')));
    await tester.pumpAndSettle();

    expect(store.savedModes, [ThemeMode.dark]);
    final radioGroup = tester.widget<RadioGroup<ThemeMode>>(
      find.byKey(const ValueKey('theme-mode-radio-group')),
    );
    expect(radioGroup.groupValue, ThemeMode.dark);
    expect(tester.takeException(), isNull);
  });

  testWidgets('저장 실패 시 이전 화면 모드로 되돌리고 안내한다', (tester) async {
    await pumpMore(
      tester,
      overrides: [
        themeModePreferencesStoreProvider.overrideWithValue(
          _FailingThemeModeStore(),
        ),
      ],
    );

    await tester.tap(find.byKey(const ValueKey('more-theme-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('theme-mode-light')));
    await tester.pumpAndSettle();

    expect(
      find.text('화면 모드를 저장하지 못했어요. 이전 설정으로 되돌렸습니다.'),
      findsOneWidget,
    );
    final radioGroup = tester.widget<RadioGroup<ThemeMode>>(
      find.byKey(const ValueKey('theme-mode-radio-group')),
    );
    expect(radioGroup.groupValue, ThemeMode.system);
  });

  testWidgets('320pt와 200% 글자에서도 화면 모드 문구가 모두 노출된다', (tester) async {
    await pumpMore(
      tester,
      size: const Size(320, 568),
      textScale: 2,
    );

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('more-theme-mode')),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await Scrollable.ensureVisible(
      tester.element(find.byKey(const ValueKey('more-theme-mode'))),
      alignment: 0.5,
      duration: Duration.zero,
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const ValueKey('more-theme-mode')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('기기의 화면 설정을 따라 자동으로 전환합니다.'), findsOneWidget);
    expect(find.text('기기 설정과 관계없이 밝은 화면을 사용합니다.'), findsOneWidget);
    expect(find.text('기기 설정과 관계없이 어두운 화면을 사용합니다.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('데이터 내보내기는 백엔드 export 후 JSON 공유 액션을 호출한다', (tester) async {
    var exportCalled = false;
    Map<String, dynamic>? sharedData;

    await pumpMore(
      tester,
      overrides: [
        exportMyDataProvider.overrideWithValue(() async {
          exportCalled = true;
          return {'format': 'dear-data-export-v1'};
        }),
        shareDataExportProvider.overrideWithValue(
          (data, {sharePositionOrigin}) async {
            sharedData = data;
          },
        ),
      ],
    );

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('more-export')),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await Scrollable.ensureVisible(
      tester.element(find.byKey(const ValueKey('more-export'))),
      alignment: 0.5,
      duration: Duration.zero,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('more-export')));
    await tester.pumpAndSettle();

    expect(exportCalled, isTrue);
    expect(sharedData, {'format': 'dear-data-export-v1'});
  });

  testWidgets('커플 연결 해제는 영향 확인 뒤 서버 액션을 실행한다', (tester) async {
    var disconnectCalled = false;
    await pumpMore(
      tester,
      overrides: [
        disconnectMyCoupleProvider.overrideWithValue(() async {
          disconnectCalled = true;
        }),
      ],
    );

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('more-disconnect')),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await Scrollable.ensureVisible(
      tester.element(find.byKey(const ValueKey('more-disconnect'))),
      alignment: 0.5,
      duration: Duration.zero,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('more-disconnect')));
    await tester.pumpAndSettle();

    expect(find.text('커플 연결을 해제할까요?'), findsOneWidget);
    expect(find.textContaining('두 사람 모두 즉시 연결이 해제'), findsOneWidget);
    expect(disconnectCalled, isFalse);

    await tester.tap(find.widgetWithText(FilledButton, '연결 해제'));
    await tester.pumpAndSettle();

    expect(disconnectCalled, isTrue);
    expect(find.text('pairing-destination'), findsOneWidget);
  });

  testWidgets('계정 삭제는 복구 불가 범위와 확인 문구를 요구한다', (tester) async {
    var deleteCalled = false;
    await pumpMore(
      tester,
      overrides: [
        deleteMyAccountProvider.overrideWithValue(() async {
          deleteCalled = true;
        }),
      ],
    );

    final deleteTile = find.byKey(const ValueKey('more-delete-account'));
    await tester.scrollUntilVisible(
      deleteTile,
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await Scrollable.ensureVisible(
      tester.element(deleteTile),
      alignment: 0.5,
      duration: Duration.zero,
    );
    await tester.pumpAndSettle();
    await tester.tap(deleteTile);
    await tester.pumpAndSettle();

    expect(find.text('계정을 영구 삭제할까요?'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsWidgets);
    expect(find.textContaining('내가 올린 파일이 삭제'), findsOneWidget);
    final confirmationMessage = tester.widget<Text>(
      find.byKey(const ValueKey('danger-confirmation-message')),
    );
    expect(confirmationMessage.data, contains('데이터 내보내기'));
    expect(deleteCalled, isFalse);

    final confirmButton = find.byKey(const ValueKey('danger-confirm-button'));
    expect(tester.widget<FilledButton>(confirmButton).onPressed, isNull);

    await tester.enterText(
      find.byKey(const ValueKey('danger-confirmation-input')),
      '삭제',
    );
    await tester.pump();
    expect(tester.widget<FilledButton>(confirmButton).onPressed, isNull);

    await tester.enterText(
      find.byKey(const ValueKey('danger-confirmation-input')),
      '계정 삭제',
    );
    await tester.pump();
    expect(tester.widget<FilledButton>(confirmButton).onPressed, isNotNull);

    await tester.tap(confirmButton);
    await tester.pumpAndSettle();

    expect(deleteCalled, isTrue);
    expect(find.text('auth-destination'), findsOneWidget);
  });

  testWidgets('프로필 편집은 별도 상세 경로로 이동한다', (tester) async {
    await pumpMore(tester);

    await tester.tap(find.byKey(const ValueKey('more-profile-edit')));
    await tester.pumpAndSettle();

    expect(find.text('profile-edit-detail'), findsOneWidget);
  });

  testWidgets('큰 글자에서도 더보기 핵심 작업이 레이아웃 오류 없이 노출된다', (tester) async {
    await pumpMore(tester, textScale: 2);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('more-delete-account')),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await Scrollable.ensureVisible(
      tester.element(find.byKey(const ValueKey('more-delete-account'))),
      alignment: 0.5,
      duration: Duration.zero,
    );
    await tester.pumpAndSettle();

    expect(find.text('계정 삭제'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('다크 모드에서 핵심 surface·text와 위험 작업이 의미 색상을 사용한다', (tester) async {
    final theme = AppTheme.dark();
    final scheme = theme.colorScheme;
    await pumpMore(tester, theme: theme);

    final profileCard = find.byKey(const ValueKey('more-profile-card-surface'));
    final profileSurface = tester.widget<Container>(
      find.descendant(of: profileCard, matching: find.byType(Container)).first,
    );
    final profileDecoration = profileSurface.decoration! as BoxDecoration;
    expect(profileDecoration.color, scheme.surface);
    expect(profileDecoration.border!.top.color, scheme.outlineVariant);

    final avatar = tester.widget<CircleAvatar>(
      find.descendant(of: profileCard, matching: find.byType(CircleAvatar)),
    );
    expect(avatar.backgroundColor, scheme.primaryContainer);
    expect((avatar.child! as Icon).color, scheme.onPrimaryContainer);

    final feature = find.byKey(const ValueKey('more-anniversary'));
    final featureSurface = tester.widget<Material>(
      find.descendant(of: feature, matching: find.byType(Material)).first,
    );
    expect(featureSurface.color, scheme.surface);
    expect(
      tester
          .widget<Text>(
            find.descendant(of: feature, matching: find.text('기념일')),
          )
          .style!
          .color,
      scheme.onSurface,
    );

    final deleteTile = find.byKey(const ValueKey('more-delete-account'));
    await tester.scrollUntilVisible(
      deleteTile,
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    final dangerSurface = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('more-danger-group-surface')),
    );
    final dangerDecoration = dangerSurface.decoration as BoxDecoration;
    expect(dangerDecoration.color, scheme.errorContainer);
    expect(dangerDecoration.border!.top.color, scheme.error);
    expect(
      tester
          .widget<Icon>(
            find.descendant(
              of: deleteTile,
              matching: find.byIcon(Icons.person_remove_outlined),
            ),
          )
          .color,
      scheme.error,
    );
    expect(
      tester
          .widget<Text>(
            find.descendant(of: deleteTile, matching: find.text('계정 삭제')),
          )
          .style!
          .color,
      scheme.onErrorContainer,
    );

    await tester.tap(deleteTile);
    await tester.pumpAndSettle();

    final dialog = find.byType(AlertDialog);
    expect(
      tester
          .widget<Icon>(
            find.descendant(
              of: dialog,
              matching: find.byIcon(Icons.warning_amber_rounded),
            ),
          )
          .color,
      scheme.error,
    );
    final dangerButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('danger-confirm-button')),
    );
    expect(
      dangerButton.style!.backgroundColor!.resolve(<WidgetState>{}),
      scheme.error,
    );
    expect(
      dangerButton.style!.foregroundColor!.resolve(<WidgetState>{}),
      scheme.onError,
    );
    expect(tester.takeException(), isNull);
  });
}

class _RecordingThemeModeStore implements ThemeModePreferencesStore {
  final savedModes = <ThemeMode>[];

  @override
  Future<ThemeMode> load() async => ThemeMode.system;

  @override
  Future<void> save(ThemeMode mode) async {
    savedModes.add(mode);
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
