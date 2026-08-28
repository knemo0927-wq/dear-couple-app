import 'dart:math' as math;

import 'package:couple_chat_app/src/common/app_theme.dart';
import 'package:couple_chat_app/src/common/dear_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Dear design tokens', () {
    test('readable text and interactive outline contrast meet their roles', () {
      expect(
          _contrast(DearColors.placeholder, DearColors.card), greaterThan(4.5));
      expect(
          _contrast(DearColors.secondary, DearColors.card), greaterThan(4.5));
      expect(
          _contrast(DearColors.outlineStrong, DearColors.card), greaterThan(3));
      expect(DearColors.placeholder, isNot(DearColors.secondary));
      expect(DearColors.placeholder, isNot(DearColors.disabled));
    });

    test('canonical radius aliases preserve the existing API', () {
      expect(DearRadii.chip, 14);
      expect(DearRadii.control, 18);
      expect(DearRadii.card, 22);
      expect(DearRadii.sheet, 30);
      expect(DearRadii.pill, 999);
      expect(DearRadii.small, DearRadii.chip);
      expect(DearRadii.medium, DearRadii.control);
      expect(DearRadii.large, DearRadii.card);
    });

    test('type, spacing, touch, icon and motion scales stay canonical', () {
      expect(DearTextStyles.displayDday.fontSize, 48);
      expect(DearTextStyles.title.fontSize, 24);
      expect(DearTextStyles.titleSmall.fontSize, 18);
      expect(DearTextStyles.body.fontSize, 16);
      expect(DearTextStyles.bodySmall.fontSize, 14);
      expect(DearTextStyles.label.fontSize, 13);
      expect(DearSpacing.space24, 24);
      expect(DearTouchTargets.minimum, 44);
      expect(DearTouchTargets.spacing, 8);
      expect(DearIconSizes.medium, 24);
      expect(DearMotion.standard, const Duration(milliseconds: 180));
    });

    test('light theme uses readable placeholder and control boundaries', () {
      final theme = AppTheme.light();
      final input = theme.inputDecorationTheme;
      final enabledBorder = input.enabledBorder! as OutlineInputBorder;
      final cardShape = theme.cardTheme.shape! as RoundedRectangleBorder;
      final outlinedSide = theme.outlinedButtonTheme.style!.side!.resolve({});

      expect(input.hintStyle!.color, DearColors.placeholder);
      expect(input.labelStyle!.color, DearColors.secondary);
      expect(enabledBorder.borderSide.color, DearColors.outlineStrong);
      expect(enabledBorder.borderRadius.topLeft.x, DearRadii.control);
      expect(cardShape.borderRadius, BorderRadius.circular(DearRadii.card));
      expect(outlinedSide!.color, DearColors.outlineStrong);
      expect(theme.colorScheme.outline, DearColors.outlineStrong);
    });
  });

  testWidgets('DearMotion removes duration when animations are disabled',
      (tester) async {
    late BuildContext capturedContext;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              capturedContext = context;
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    expect(
      DearMotion.duration(capturedContext, DearMotion.emphasized),
      Duration.zero,
    );
  });

  testWidgets('DearIconButton keeps a 44pt target and a tappable semantic name',
      (tester) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(
            child: DearIconButton(
              key: const Key('dear-icon-button'),
              tooltip: '알림 열기',
              semanticLabel: '읽지 않은 알림 열기',
              icon: const Icon(Icons.notifications_none_rounded),
              onPressed: () => taps++,
            ),
          ),
        ),
      ),
    );

    final size = tester.getSize(find.byKey(const Key('dear-icon-button')));
    final node = tester.getSemantics(find.byKey(const Key('dear-icon-button')));
    final iconButton = tester.widget<IconButton>(find.byType(IconButton));

    expect(size.width, greaterThanOrEqualTo(DearTouchTargets.minimum));
    expect(size.height, greaterThanOrEqualTo(DearTouchTargets.minimum));
    expect(iconButton.tooltip, '알림 열기');
    expect(node.label, '읽지 않은 알림 열기');
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);

    await tester.tap(find.byKey(const Key('dear-icon-button')));
    expect(taps, 1);
    semantics.dispose();
  });

  testWidgets('DearAsyncSection preserves content through error and retry',
      (tester) async {
    final semantics = tester.ensureSemantics();
    var retries = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: DearAsyncSection(
            status: DearAsyncSectionStatus.error,
            errorMessage: '일부 사진을 불러오지 못했어요.',
            onRetry: () => retries++,
            content: const Text('마지막으로 불러온 사진'),
          ),
        ),
      ),
    );

    expect(find.text('마지막으로 불러온 사진'), findsOneWidget);
    expect(find.text('일부 사진을 불러오지 못했어요.'), findsOneWidget);
    final node = tester.getSemantics(find.byType(DearInlineError));
    expect(node.label, contains('일부 사진을 불러오지 못했어요.'));

    await tester.tap(find.text('다시 시도'));
    expect(retries, 1);
    semantics.dispose();
  });

  testWidgets('DearAsyncSection exposes retry busy without dropping content',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: DearAsyncSection(
            status: DearAsyncSectionStatus.error,
            errorMessage: '연결이 불안정해요.',
            retrying: true,
            content: Text('저장된 설정'),
          ),
        ),
      ),
    );

    expect(find.text('저장된 설정'), findsOneWidget);
    expect(find.text('다시 불러오는 중'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
        tester.widget<TextButton>(find.byType(TextButton)).onPressed, isNull);
  });

  testWidgets(
      'DearAsyncSection distinguishes skeleton and actionable empty state',
      (tester) async {
    var emptyActions = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: DearAsyncSection(
            status: DearAsyncSectionStatus.loading,
            loadingLabel: '앨범을 불러오는 중',
            skeleton: SizedBox(
              key: Key('album-skeleton'),
              width: 120,
              height: 80,
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('album-skeleton')), findsOneWidget);
    expect(find.byType(DearLoadingState), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: DearAsyncSection(
            status: DearAsyncSectionStatus.empty,
            emptyTitle: '아직 사진이 없어요',
            emptyMessage: '첫 사진을 추가해 보세요.',
            emptyActionLabel: '사진 추가',
            onEmptyAction: () => emptyActions++,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('아직 사진이 없어요'), findsOneWidget);
    expect(find.text('첫 사진을 추가해 보세요.'), findsOneWidget);
    await tester.tap(find.text('사진 추가'));
    expect(emptyActions, 1);
  });
}

double _contrast(Color foreground, Color background) {
  final foregroundLuminance = _relativeLuminance(foreground);
  final backgroundLuminance = _relativeLuminance(background);
  final lighter = math.max(foregroundLuminance, backgroundLuminance);
  final darker = math.min(foregroundLuminance, backgroundLuminance);
  return (lighter + 0.05) / (darker + 0.05);
}

double _relativeLuminance(Color color) {
  final argb = color.toARGB32();
  double linearized(int shift) {
    final channel = ((argb >> shift) & 0xFF) / 255;
    return channel <= 0.04045
        ? channel / 12.92
        : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();
  }

  final red = linearized(16);
  final green = linearized(8);
  final blue = linearized(0);
  return red * 0.2126 + green * 0.7152 + blue * 0.0722;
}
