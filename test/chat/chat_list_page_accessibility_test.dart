import 'package:couple_chat_app/src/features/anniversary/data/anniversary_providers.dart';
import 'package:couple_chat_app/src/features/auth/data/auth_providers.dart';
import 'package:couple_chat_app/src/features/auth/data/auth_repository.dart';
import 'package:couple_chat_app/src/features/chat/data/chat_providers.dart';
import 'package:couple_chat_app/src/features/chat/data/chat_repository.dart';
import 'package:couple_chat_app/src/features/chat/data/memory_album_providers.dart';
import 'package:couple_chat_app/src/features/chat/data/memory_album_repository.dart';
import 'package:couple_chat_app/src/features/chat/presentation/chat_list_page.dart';
import 'package:couple_chat_app/src/features/chat/presentation/chat_shell_page.dart';
import 'package:couple_chat_app/src/features/notifications/data/notification_inbox.dart';
import 'package:couple_chat_app/src/features/settings/data/couple_prefs_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('홈은 390x844·200% 글자와 긴 닉네임에서 핵심 카드가 넘치지 않는다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const coupleId = '11111111-1111-4111-8111-111111111111';
    final relationshipStart =
        DateUtils.dateOnly(DateTime.now().subtract(const Duration(days: 981)));
    final customItem = AnniversaryItem(
      id: 'custom-1',
      coupleId: coupleId,
      title: '처음 함께 떠난 여름 여행',
      eventDate: DateUtils.dateOnly(
        DateTime.now().add(const Duration(days: 12)),
      ),
      createdAt: DateTime(2026, 1, 1),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myProfileProvider.overrideWith(
            (ref) async => const ProfileInfo(
              userId: 'user-1',
              nickname: '아주 긴 닉네임을 사용하는 사용자',
              pairingCode: 'ABCD',
              coupleId: coupleId,
              avatarPath: null,
            ),
          ),
          anniversaryDateProvider.overrideWith(
            (ref) => Stream.value(relationshipStart),
          ),
          anniversaryItemsProvider.overrideWith(
            (ref, id) => Stream.value([customItem]),
          ),
          chatUnreadCountProvider.overrideWith(
            (ref, id) => Stream.value(3),
          ),
          chatConversationPreviewProvider.overrideWith(
            (ref, id) => Stream.value(
              ChatConversationPreview(
                text: '오늘 저녁에 같이 산책할까?',
                createdAt: DateTime.now(),
              ),
            ),
          ),
          notificationInboxProvider.overrideWith(
            (ref, id) => Stream.value(const <NotificationInboxItem>[]),
          ),
          coupleAvatarUrlMapProvider.overrideWith(
            (ref, id) => Stream.value(const <String, String>{}),
          ),
          coupleNicknameMapProvider.overrideWith(
            (ref, id) => Stream.value(
              const <String, String>{
                'user-1': '하루',
                'user-2': '아주 긴 이름의 상대방',
              },
            ),
          ),
          recentMemoryAlbumPhotosProvider.overrideWith(
            (ref, id) => Stream.value(const <MemoryAlbumPhoto>[]),
          ),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
            ),
            child: child!,
          ),
          home: const ChatListPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('우리의 연애'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('relationship-hero'))).height,
      greaterThan(168),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('채팅방 헤더는 390x844·200% 글자에서 넘치지 않는다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const coupleId = '11111111-1111-4111-8111-111111111111';
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatCurrentUserIdProvider.overrideWithValue('user-1'),
          coupleNicknameMapProvider.overrideWith(
            (ref, id) => Stream.value(
              const <String, String>{
                'user-1': '하루',
                'user-2': '아주 긴 이름의 상대방',
              },
            ),
          ),
          coupleAvatarUrlMapProvider.overrideWith(
            (ref, id) => Stream.value(const <String, String>{}),
          ),
          anniversaryDateProvider.overrideWith(
            (ref) => Stream.value(DateTime(2024, 1, 1)),
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
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
            ),
            child: child!,
          ),
          home: const ChatShellPage(coupleId: coupleId),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('아주 긴 이름의 상대방'), findsOneWidget);
    expect(find.text('온라인'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
