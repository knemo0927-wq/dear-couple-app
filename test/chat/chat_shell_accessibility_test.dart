import 'package:couple_chat_app/src/common/app_theme.dart';
import 'package:couple_chat_app/src/common/dear_design.dart';
import 'package:couple_chat_app/src/features/auth/data/auth_providers.dart';
import 'package:couple_chat_app/src/features/chat/data/chat_providers.dart';
import 'package:couple_chat_app/src/features/chat/data/chat_repository.dart';
import 'package:couple_chat_app/src/features/chat/presentation/chat_shell_page.dart';
import 'package:couple_chat_app/src/features/settings/data/couple_prefs_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const partnerName = '아주 긴 이름의 상대방';

  testWidgets('320pt·200% 헤더는 이름을 줄이지 않고 조작을 44pt로 유지한다', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pumpChatShell(
      tester,
      width: 320,
      textScale: 2,
      partnerName: partnerName,
    );

    final name = tester.widget<Text>(
      find.byKey(const ValueKey('chat-header-partner-name')),
    );
    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    final backSize =
        tester.getSize(find.byKey(const ValueKey('chat-header-back')));
    final moreSize =
        tester.getSize(find.byKey(const ValueKey('chat-header-more')));
    final backNode =
        tester.getSemantics(find.byKey(const ValueKey('chat-header-back')));
    final moreNode =
        tester.getSemantics(find.byKey(const ValueKey('chat-header-more')));

    expect(name.maxLines, isNull);
    expect(name.overflow, TextOverflow.visible);
    expect(_renderedLineCount(tester, partnerName), greaterThanOrEqualTo(2));
    expect(appBar.toolbarHeight, greaterThan(108));
    expect(appBar.actions, hasLength(1));
    expect(backSize.width, greaterThanOrEqualTo(DearTouchTargets.minimum));
    expect(backSize.height, greaterThanOrEqualTo(DearTouchTargets.minimum));
    expect(moreSize.width, greaterThanOrEqualTo(DearTouchTargets.minimum));
    expect(moreSize.height, greaterThanOrEqualTo(DearTouchTargets.minimum));
    expect(backNode.label, '채팅 목록으로 돌아가기');
    expect(
      backNode.getSemanticsData().hasAction(SemanticsAction.tap),
      isTrue,
    );
    expect(moreNode.label, '더보기');
    expect(
      moreNode.getSemanticsData().hasAction(SemanticsAction.tap),
      isTrue,
    );
    expect(
      tester
          .widget<DearIconButton>(
            find.byKey(const ValueKey('chat-header-back')),
          )
          .tooltip,
      '뒤로가기',
    );
    final popupMenuFinder = find.byWidgetPredicate(
      (widget) => widget is PopupMenuButton<String>,
    );
    expect(
      tester.widget<PopupMenuButton<String>>(popupMenuFinder).tooltip,
      '더보기',
    );
    _expectWithinWidth(
      tester,
      find.byKey(const ValueKey('chat-header-title')),
      320,
    );
    _expectWithinWidth(
      tester,
      find.byKey(const ValueKey('chat-header-more')),
      320,
    );
    final exception = tester.takeException();
    semantics.dispose();
    expect(exception, isNull);
  });

  testWidgets('375pt·200% 헤더는 D-day를 제목 아래로 재배치하고 본문 공간을 조정한다', (tester) async {
    await _pumpChatShell(
      tester,
      width: 375,
      textScale: 2,
      partnerName: partnerName,
    );

    final nameFinder = find.byKey(const ValueKey('chat-header-partner-name'));
    final ddayFinder = find.byKey(const ValueKey('chat-header-dday'));
    final titleFinder = find.byKey(const ValueKey('chat-header-title'));
    final appBarRect = tester.getRect(find.byType(AppBar));
    final contentRect = tester.getRect(find.byType(DearBackground));

    expect(_renderedLineCount(tester, partnerName), greaterThanOrEqualTo(2));
    expect(
      find.descendant(of: titleFinder, matching: ddayFinder),
      findsOneWidget,
    );
    expect(tester.getRect(ddayFinder).top,
        greaterThan(tester.getRect(nameFinder).bottom));
    expect(contentRect.top, greaterThanOrEqualTo(appBarRect.bottom - 0.1));
    _expectWithinWidth(tester, titleFinder, 375);
    _expectWithinWidth(tester, ddayFinder, 375);
    expect(tester.takeException(), isNull);
  });

  testWidgets('일반 글자 배율은 기존 72pt·한 줄 헤더를 유지한다', (tester) async {
    await _pumpChatShell(
      tester,
      width: 375,
      textScale: 1,
      partnerName: partnerName,
    );

    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    final name = tester.widget<Text>(
      find.byKey(const ValueKey('chat-header-partner-name')),
    );

    expect(appBar.toolbarHeight, 72);
    expect(appBar.actions, hasLength(1));
    expect(name.maxLines, 1);
    expect(name.overflow, TextOverflow.ellipsis);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('chat-header-title')),
        matching: find.byKey(const ValueKey('chat-header-dday')),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpChatShell(
  WidgetTester tester, {
  required double width,
  required double textScale,
  required String partnerName,
}) async {
  // Keep vertical room for ChatPage's separately tested composer; this suite
  // targets the shell header at compact iPhone widths.
  tester.view.physicalSize = Size(width, 1024);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  const coupleId = '11111111-1111-4111-8111-111111111111';
  final relationshipStart =
      DateUtils.dateOnly(DateTime.now().subtract(const Duration(days: 981)));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        chatCurrentUserIdProvider.overrideWithValue('user-1'),
        coupleNicknameMapProvider.overrideWith(
          (ref, id) => Stream.value(
            <String, String>{
              'user-1': '하루',
              'user-2': partnerName,
            },
          ),
        ),
        coupleAvatarUrlMapProvider.overrideWith(
          (ref, id) => Stream.value(const <String, String>{}),
        ),
        anniversaryDateProvider.overrideWith(
          (ref) => Stream.value(relationshipStart),
        ),
        chatLatestMessageAtProvider.overrideWith(
          (ref, id) => Stream.value(DateTime.now()),
        ),
        chatPartnerOnlineProvider.overrideWith(
          (ref, id) => Stream.value(true),
        ),
        chatPartnerReadMarkerProvider.overrideWith(
          (ref, id) => Stream.value(null),
        ),
        chatWatchMessagesProvider.overrideWithValue(
          (id) => Stream.value(const <ChatMessage>[]),
        ),
        chatWatchReactionMessageIdsProvider.overrideWithValue(
          (id) => const Stream<int>.empty(),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: const ChatShellPage(coupleId: coupleId),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

int _renderedLineCount(WidgetTester tester, String text) {
  final paragraph = tester.renderObject<RenderParagraph>(
    find.byKey(const ValueKey('chat-header-partner-name')),
  );
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: text.length),
  );
  return boxes.map((box) => box.top.round()).toSet().length;
}

void _expectWithinWidth(
  WidgetTester tester,
  Finder finder,
  double width,
) {
  final rect = tester.getRect(finder);
  expect(rect.left, greaterThanOrEqualTo(-0.1));
  expect(rect.right, lessThanOrEqualTo(width + 0.1));
}
