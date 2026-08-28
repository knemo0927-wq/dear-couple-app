import 'dart:async';
import 'dart:typed_data';

import 'package:couple_chat_app/src/features/chat/data/chat_providers.dart';
import 'package:couple_chat_app/src/features/chat/data/chat_repository.dart';
import 'package:couple_chat_app/src/features/chat/presentation/chat_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

const coupleId = '11111111-1111-4111-8111-111111111111';

ChatUploadImageAction controlledUpload(ChatSendImageAction action) {
  return ({
    required coupleId,
    required bytes,
    required extension,
    required idempotencyKey,
    required isCancelled,
    onProgress,
  }) async {
    if (isCancelled()) return ChatImageSendOutcome.cancelled;
    onProgress?.call(0.2);
    await action(coupleId: coupleId, bytes: bytes, extension: extension);
    if (isCancelled()) return ChatImageSendOutcome.cancelled;
    onProgress?.call(1);
    return ChatImageSendOutcome.sent;
  };
}

ChatSendReplyTextAction controlledReplyText(ChatSendTextAction action) {
  return ({required coupleId, required text, replyToMessageId}) =>
      action(coupleId: coupleId, text: text);
}

Future<void> _pickSinglePhoto(WidgetTester tester) async {
  final attachmentButton = find.byKey(const Key('chat-attachment-button'));
  expect(attachmentButton, findsOneWidget);
  expect(tester.getSize(attachmentButton).width, greaterThanOrEqualTo(44));
  expect(tester.getSize(attachmentButton).height, greaterThanOrEqualTo(44));

  await tester.tap(attachmentButton);
  await tester.pumpAndSettle();

  final singleChoice = find.text('사진 한 장 선택');
  expect(singleChoice, findsOneWidget);
  expect(find.text('사진 여러 장 선택'), findsOneWidget);
  expect(
    find.ancestor(of: singleChoice, matching: find.byType(SafeArea)),
    findsWidgets,
  );

  await tester.tap(singleChoice);
  await tester.pumpAndSettle();
}

Future<void> _pickMultiplePhotos(WidgetTester tester) async {
  final attachmentButton = find.byKey(const Key('chat-attachment-button'));
  expect(attachmentButton, findsOneWidget);
  expect(tester.getSize(attachmentButton).width, greaterThanOrEqualTo(44));
  expect(tester.getSize(attachmentButton).height, greaterThanOrEqualTo(44));

  await tester.tap(attachmentButton);
  await tester.pumpAndSettle();

  expect(find.text('사진 한 장 선택'), findsOneWidget);
  final multipleChoice = find.text('사진 여러 장 선택');
  expect(multipleChoice, findsOneWidget);

  await tester.tap(multipleChoice);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('텍스트 전송 실패 시 다시 시도 버튼이 노출되고 재시도에 성공하면 사라진다', (tester) async {
    var sendCount = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatWatchMessagesProvider.overrideWithValue(
            (_) => Stream<List<ChatMessage>>.value(const []),
          ),
          chatCurrentUserIdProvider.overrideWithValue('user-1'),
          chatSendReplyTextProvider.overrideWithValue(controlledReplyText(({
            required String coupleId,
            required String text,
          }) async {
            sendCount++;
            if (sendCount == 1) {
              throw Exception('SocketException: Failed host lookup');
            }
          })),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: ChatPage(coupleId: '11111111-1111-4111-8111-111111111111'),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '안녕');
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(sendCount, 1);
    expect(find.text('다시 시도'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, '다시 시도'));
    await tester.pumpAndSettle();

    expect(sendCount, 2);
    expect(find.text('다시 시도'), findsNothing);
  });

  testWidgets('이미지 선택 후 미리보기가 노출되고 취소할 수 있다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatWatchMessagesProvider.overrideWithValue(
            (_) => Stream<List<ChatMessage>>.value(const []),
          ),
          chatCurrentUserIdProvider.overrideWithValue('user-1'),
          chatPickImageProvider.overrideWithValue(() async {
            return PickedChatImage(
              bytes: Uint8List.fromList([1, 2, 3]),
              extension: 'png',
            );
          }),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: ChatPage(coupleId: '11111111-1111-4111-8111-111111111111'),
          ),
        ),
      ),
    );

    await _pickSinglePhoto(tester);

    expect(find.text('이미지 미리보기 (PNG)'), findsOneWidget);
    expect(find.byKey(const Key('pending-image-thumbnail')), findsOneWidget);
    expect(find.widgetWithText(TextButton, '다른 이미지'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '취소'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '이미지 전송'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '취소'));
    await tester.pumpAndSettle();

    expect(find.text('이미지 미리보기 (PNG)'), findsNothing);
    expect(find.byKey(const Key('pending-image-thumbnail')), findsNothing);
    expect(find.widgetWithText(FilledButton, '이미지 전송'), findsNothing);
  });

  testWidgets('다른 이미지 버튼으로 재선택하면 마지막으로 고른 이미지가 전송된다', (tester) async {
    var pickCount = 0;
    String? sentExtension;
    Uint8List? sentBytes;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatWatchMessagesProvider.overrideWithValue(
            (_) => Stream<List<ChatMessage>>.value(const []),
          ),
          chatCurrentUserIdProvider.overrideWithValue('user-1'),
          chatPickImageProvider.overrideWithValue(() async {
            pickCount++;
            if (pickCount == 1) {
              return PickedChatImage(
                bytes: Uint8List.fromList([1, 2, 3]),
                extension: 'jpg',
              );
            }
            return PickedChatImage(
              bytes: Uint8List.fromList([9, 8, 7]),
              extension: 'webp',
            );
          }),
          chatUploadImageProvider.overrideWithValue(controlledUpload(({
            required String coupleId,
            required Uint8List bytes,
            required String extension,
          }) async {
            sentBytes = bytes;
            sentExtension = extension;
          })),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: ChatPage(coupleId: '11111111-1111-4111-8111-111111111111'),
          ),
        ),
      ),
    );

    await _pickSinglePhoto(tester);
    expect(find.text('이미지 미리보기 (JPG)'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '다른 이미지'));
    await tester.pumpAndSettle();
    expect(find.text('이미지 미리보기 (WEBP)'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '이미지 전송'));
    await tester.pumpAndSettle();

    expect(sentExtension, 'webp');
    expect(sentBytes, isNotNull);
    expect(sentBytes!.first, 9);
  });

  testWidgets('gif 이미지를 선택하면 형식 오류를 노출하고 미리보기를 표시하지 않는다', (tester) async {
    var sendImageCount = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatWatchMessagesProvider.overrideWithValue(
            (_) => Stream<List<ChatMessage>>.value(const []),
          ),
          chatCurrentUserIdProvider.overrideWithValue('user-1'),
          chatPickImageProvider.overrideWithValue(() async {
            return PickedChatImage(
              bytes: Uint8List.fromList([1, 2, 3]),
              extension: 'gif',
            );
          }),
          chatUploadImageProvider.overrideWithValue(controlledUpload(({
            required String coupleId,
            required Uint8List bytes,
            required String extension,
          }) async {
            sendImageCount++;
          })),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: ChatPage(coupleId: '11111111-1111-4111-8111-111111111111'),
          ),
        ),
      ),
    );

    await _pickSinglePhoto(tester);

    expect(find.text('JPG, PNG, WEBP 형식 이미지만 전송할 수 있어요.'), findsOneWidget);
    expect(find.byKey(const Key('pending-image-thumbnail')), findsNothing);
    expect(sendImageCount, 0);
  });

  testWidgets('5MB 초과 이미지는 미리보기에서 전송 지연 경고를 노출한다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatWatchMessagesProvider.overrideWithValue(
            (_) => Stream<List<ChatMessage>>.value(const []),
          ),
          chatCurrentUserIdProvider.overrideWithValue('user-1'),
          chatPickImageProvider.overrideWithValue(() async {
            return PickedChatImage(
              bytes: Uint8List(6 * 1024 * 1024),
              extension: 'jpg',
            );
          }),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: ChatPage(coupleId: '11111111-1111-4111-8111-111111111111'),
          ),
        ),
      ),
    );

    await _pickSinglePhoto(tester);

    expect(find.textContaining('6.0 MB'), findsOneWidget);
    expect(find.text('용량이 커서 전송이 느릴 수 있어요.'), findsOneWidget);
  });

  testWidgets('8MB 초과 이미지는 전송을 차단하고 업로드 호출하지 않는다', (tester) async {
    var sendImageCount = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatWatchMessagesProvider.overrideWithValue(
            (_) => Stream<List<ChatMessage>>.value(const []),
          ),
          chatCurrentUserIdProvider.overrideWithValue('user-1'),
          chatPickImageProvider.overrideWithValue(() async {
            return PickedChatImage(
              bytes: Uint8List(8 * 1024 * 1024 + 1),
              extension: 'jpg',
            );
          }),
          chatUploadImageProvider.overrideWithValue(controlledUpload(({
            required String coupleId,
            required Uint8List bytes,
            required String extension,
          }) async {
            sendImageCount++;
          })),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: ChatPage(coupleId: '11111111-1111-4111-8111-111111111111'),
          ),
        ),
      ),
    );

    await _pickSinglePhoto(tester);

    expect(find.text('8MB 초과 이미지는 전송할 수 없어요.'), findsOneWidget);

    final sendButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '이미지 전송'),
    );
    expect(sendButton.onPressed, isNull);
    expect(sendImageCount, 0);
  });

  testWidgets('이미지 전송 실패 시 다시 시도로 이미지 업로드를 재실행한다', (tester) async {
    var sendImageCount = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatWatchMessagesProvider.overrideWithValue(
            (_) => Stream<List<ChatMessage>>.value(const []),
          ),
          chatCurrentUserIdProvider.overrideWithValue('user-1'),
          chatPickImageProvider.overrideWithValue(() async {
            return PickedChatImage(
              bytes: Uint8List.fromList([1, 2, 3]),
              extension: 'png',
            );
          }),
          chatUploadImageProvider.overrideWithValue(controlledUpload(({
            required String coupleId,
            required Uint8List bytes,
            required String extension,
          }) async {
            sendImageCount++;
            if (sendImageCount == 1) {
              throw Exception('upload failed');
            }
          })),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: ChatPage(coupleId: '11111111-1111-4111-8111-111111111111'),
          ),
        ),
      ),
    );

    await _pickSinglePhoto(tester);
    await tester.tap(find.widgetWithText(FilledButton, '이미지 전송'));
    await tester.pumpAndSettle();

    expect(sendImageCount, 1);
    expect(find.text('다시 시도'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, '다시 시도'));
    await tester.pumpAndSettle();

    expect(sendImageCount, 2);
    expect(find.text('다시 시도'), findsNothing);
  });

  testWidgets('이미지 선택을 취소하면 업로드 호출을 하지 않는다', (tester) async {
    var sendImageCount = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatWatchMessagesProvider.overrideWithValue(
            (_) => Stream<List<ChatMessage>>.value(const []),
          ),
          chatCurrentUserIdProvider.overrideWithValue('user-1'),
          chatPickImageProvider.overrideWithValue(() async => null),
          chatUploadImageProvider.overrideWithValue(controlledUpload(({
            required String coupleId,
            required Uint8List bytes,
            required String extension,
          }) async {
            sendImageCount++;
          })),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: ChatPage(coupleId: '11111111-1111-4111-8111-111111111111'),
          ),
        ),
      ),
    );

    await _pickSinglePhoto(tester);

    expect(sendImageCount, 0);
    expect(find.text('다시 시도'), findsNothing);
  });

  testWidgets('이미지 업로드 중에는 진행 안내 문구를 노출한다', (tester) async {
    final uploadCompleter = Completer<void>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatWatchMessagesProvider.overrideWithValue(
            (_) => Stream<List<ChatMessage>>.value(const []),
          ),
          chatCurrentUserIdProvider.overrideWithValue('user-1'),
          chatPickImageProvider.overrideWithValue(() async {
            return PickedChatImage(
              bytes: Uint8List.fromList([1, 2, 3]),
              extension: 'png',
            );
          }),
          chatUploadImageProvider.overrideWithValue(controlledUpload(({
            required String coupleId,
            required Uint8List bytes,
            required String extension,
          }) {
            return uploadCompleter.future;
          })),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: ChatPage(coupleId: '11111111-1111-4111-8111-111111111111'),
          ),
        ),
      ),
    );

    await _pickSinglePhoto(tester);
    await tester.tap(find.widgetWithText(FilledButton, '이미지 전송'));
    await tester.pump();

    expect(find.text('이미지 업로드 중...'), findsOneWidget);

    uploadCompleter.complete();
    await tester.pumpAndSettle();

    expect(find.text('이미지 업로드 중...'), findsNothing);
  });

  testWidgets('여러 사진을 선택하면 가로 큐에 표시하고 순서대로 전송한다', (tester) async {
    var sentCount = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatWatchMessagesProvider.overrideWithValue(
            (_) => Stream<List<ChatMessage>>.value(const []),
          ),
          chatCurrentUserIdProvider.overrideWithValue('user-1'),
          chatPickImagesProvider.overrideWithValue(() async {
            return List.generate(
              3,
              (index) => PickedChatImage(
                bytes: Uint8List.fromList([index + 1, 2, 3]),
                extension: 'jpg',
              ),
            );
          }),
          chatUploadImageProvider.overrideWithValue(controlledUpload(({
            required String coupleId,
            required Uint8List bytes,
            required String extension,
          }) async {
            sentCount++;
          })),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: ChatPage(coupleId: '11111111-1111-4111-8111-111111111111'),
          ),
        ),
      ),
    );

    await _pickMultiplePhotos(tester);

    expect(find.text('선택한 사진 3장'), findsOneWidget);
    expect(find.byKey(const Key('pending-image-thumbnail')), findsOneWidget);
    expect(find.byKey(const Key('pending-image-thumbnail-1')), findsOneWidget);
    expect(find.byKey(const Key('pending-image-thumbnail-2')), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '3장 전송'));
    await tester.pumpAndSettle();

    expect(sentCount, 3);
    expect(find.text('선택한 사진 3장'), findsNothing);
  });

  testWidgets('텍스트는 전송 완료 전 낙관적 말풍선과 상태를 표시한다', (tester) async {
    final completer = Completer<void>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatWatchMessagesProvider.overrideWithValue(
            (_) => Stream<List<ChatMessage>>.value(const []),
          ),
          chatCurrentUserIdProvider.overrideWithValue('user-1'),
          chatSendReplyTextProvider.overrideWithValue(controlledReplyText(({
            required String coupleId,
            required String text,
          }) =>
              completer.future)),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: ChatPage(coupleId: '11111111-1111-4111-8111-111111111111'),
          ),
        ),
      ),
    );
    final semantics = tester.ensureSemantics();

    expect(
      find.bySemanticsLabel('메시지를 입력하면 전송할 수 있어요'),
      findsOneWidget,
    );
    final disabledSend = tester.getSemantics(
      find.bySemanticsLabel('메시지를 입력하면 전송할 수 있어요'),
    );
    expect(
      disabledSend.getSemanticsData().hasAction(SemanticsAction.tap),
      isFalse,
    );

    await tester.enterText(find.byType(TextField), '곧 도착할 메시지');
    await tester.pump();
    final enabledSend = tester.getSemantics(
      find.bySemanticsLabel('메시지 전송 가능'),
    );
    expect(
      enabledSend.getSemanticsData().flagsCollection.isEnabled.toBoolOrNull(),
      isTrue,
    );
    expect(
      enabledSend.getSemanticsData().hasAction(SemanticsAction.tap),
      isTrue,
    );

    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();

    expect(find.text('곧 도착할 메시지'), findsOneWidget);
    expect(find.textContaining('전송 중'), findsOneWidget);
    final sending = tester.getSemantics(
      find.bySemanticsLabel('메시지 전송 중'),
    );
    expect(
      sending.getSemanticsData().flagsCollection.isEnabled.toBoolOrNull(),
      isFalse,
    );
    expect(sending.getSemanticsData().flagsCollection.isLiveRegion, isTrue);

    completer.complete();
    await tester.pumpAndSettle();

    expect(find.text('곧 도착할 메시지'), findsNothing);
    expect(find.textContaining('전송 중'), findsNothing);
    semantics.dispose();
  });

  testWidgets('44pt 더보기와 길게 누르기는 같은 메시지 작업 메뉴를 제공한다', (tester) async {
    final message = ChatMessage(
      id: 42,
      coupleId: '11111111-1111-4111-8111-111111111111',
      senderId: 'user-1',
      body: '기억해 줘',
      imagePath: null,
      createdAt: DateTime(2026, 7, 12, 9),
      heartCount: 0,
      isHeartedByMe: false,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatWatchMessagesProvider.overrideWithValue(
            (_) => Stream<List<ChatMessage>>.value([message]),
          ),
          chatCurrentUserIdProvider.overrideWithValue('user-1'),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: ChatPage(coupleId: '11111111-1111-4111-8111-111111111111'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final semantics = tester.ensureSemantics();

    final actionsButton = find.byKey(
      const ValueKey<String>('message-actions-42'),
    );
    expect(actionsButton, findsOneWidget);
    expect(tester.getSize(actionsButton).width, greaterThanOrEqualTo(44));
    expect(tester.getSize(actionsButton).height, greaterThanOrEqualTo(44));
    expect(
      find.bySemanticsLabel(RegExp(r'^하트 반응')),
      findsNothing,
    );

    await tester.tap(actionsButton);
    await tester.pumpAndSettle();
    expect(find.text('하트 남기기'), findsOneWidget);
    expect(find.text('답장'), findsOneWidget);
    expect(find.text('복사'), findsOneWidget);
    expect(find.text('삭제'), findsOneWidget);

    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('기억해 줘'));
    await tester.pumpAndSettle();

    expect(find.text('하트 남기기'), findsOneWidget);
    expect(find.text('답장'), findsOneWidget);
    expect(find.text('복사'), findsOneWidget);
    expect(find.text('삭제'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('하트 반응은 개수와 선택 상태를 읽고 작업 메뉴에서 취소할 수 있다', (tester) async {
    int? toggledMessageId;
    final message = ChatMessage(
      id: 43,
      coupleId: coupleId,
      senderId: 'user-2',
      body: '좋아해',
      imagePath: null,
      createdAt: DateTime(2026, 7, 12, 9),
      heartCount: 2,
      isHeartedByMe: true,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatWatchMessagesProvider.overrideWithValue(
            (_) => Stream<List<ChatMessage>>.value([message]),
          ),
          chatCurrentUserIdProvider.overrideWithValue('user-1'),
          chatToggleReactionProvider.overrideWithValue(({
            required int messageId,
          }) async {
            toggledMessageId = messageId;
          }),
        ],
        child: const MaterialApp(
          home: Scaffold(body: ChatPage(coupleId: coupleId)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final semantics = tester.ensureSemantics();

    final heart = find.bySemanticsLabel(RegExp(r'하트 반응 2개'));
    expect(heart, findsOneWidget);
    expect(
      tester
          .getSemantics(heart)
          .getSemanticsData()
          .flagsCollection
          .isToggled
          .toBoolOrNull(),
      isTrue,
    );
    expect(
      tester
          .getSemantics(heart)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );

    await tester.tap(find.byTooltip('하트 취소'));
    await tester.pump();
    expect(toggledMessageId, 43);

    await tester.tap(
      find.byKey(const ValueKey<String>('message-actions-43')),
    );
    await tester.pumpAndSettle();
    expect(find.text('하트 취소'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('같은 사진을 여러 번 고르면 큐에 한 번만 추가한다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatWatchMessagesProvider.overrideWithValue(
            (_) => Stream<List<ChatMessage>>.value(const []),
          ),
          chatCurrentUserIdProvider.overrideWithValue('user-1'),
          chatPickImagesProvider.overrideWithValue(() async {
            return [
              PickedChatImage(
                bytes: Uint8List.fromList([1, 2, 3]),
                extension: 'jpg',
              ),
              PickedChatImage(
                bytes: Uint8List.fromList([1, 2, 3]),
                extension: 'jpg',
              ),
            ];
          }),
        ],
        child: const MaterialApp(
          home: Scaffold(body: ChatPage(coupleId: coupleId)),
        ),
      ),
    );

    await _pickMultiplePhotos(tester);

    expect(find.text('이미지 미리보기 (JPG)'), findsOneWidget);
    expect(find.byKey(const Key('pending-image-thumbnail-1')), findsNothing);
    expect(find.text('이미 선택한 사진은 한 번만 추가했어요.'), findsOneWidget);
  });

  testWidgets('다중 전송 후반 실패를 재시도해도 성공한 앞 사진은 중복 전송하지 않는다', (tester) async {
    final sentOrder = <int>[];
    var secondAttempts = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatWatchMessagesProvider.overrideWithValue(
            (_) => Stream<List<ChatMessage>>.value(const []),
          ),
          chatCurrentUserIdProvider.overrideWithValue('user-1'),
          chatPickImagesProvider.overrideWithValue(() async => [
                PickedChatImage(
                  bytes: Uint8List.fromList([1]),
                  extension: 'jpg',
                ),
                PickedChatImage(
                  bytes: Uint8List.fromList([2]),
                  extension: 'jpg',
                ),
              ]),
          chatUploadImageProvider.overrideWithValue(({
            required String coupleId,
            required Uint8List bytes,
            required String extension,
            required String idempotencyKey,
            required bool Function() isCancelled,
            void Function(double progress)? onProgress,
          }) async {
            sentOrder.add(bytes.first);
            if (bytes.first == 2 && secondAttempts++ == 0) {
              throw Exception('second failed');
            }
            return ChatImageSendOutcome.sent;
          }),
        ],
        child: const MaterialApp(
          home: Scaffold(body: ChatPage(coupleId: coupleId)),
        ),
      ),
    );

    await _pickMultiplePhotos(tester);
    await tester.tap(find.widgetWithText(FilledButton, '2장 전송'));
    await tester.pumpAndSettle();

    expect(sentOrder, [1, 2]);
    expect(find.text('이미지 미리보기 (JPG)'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '다시 시도'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, '다시 시도'));
    await tester.pumpAndSettle();

    expect(sentOrder, [1, 2, 2]);
    expect(find.byKey(const Key('pending-image-thumbnail')), findsNothing);
  });

  testWidgets('업로드 중인 개별 사진 취소 요청을 전송 제어기에 전달한다', (tester) async {
    final completer = Completer<void>();
    var observedCancellation = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatWatchMessagesProvider.overrideWithValue(
            (_) => Stream<List<ChatMessage>>.value(const []),
          ),
          chatCurrentUserIdProvider.overrideWithValue('user-1'),
          chatPickImageProvider.overrideWithValue(() async => PickedChatImage(
                bytes: Uint8List.fromList([1, 2, 3]),
                extension: 'png',
              )),
          chatUploadImageProvider.overrideWithValue(({
            required String coupleId,
            required Uint8List bytes,
            required String extension,
            required String idempotencyKey,
            required bool Function() isCancelled,
            void Function(double progress)? onProgress,
          }) async {
            onProgress?.call(.3);
            await completer.future;
            observedCancellation = isCancelled();
            return observedCancellation
                ? ChatImageSendOutcome.cancelled
                : ChatImageSendOutcome.sent;
          }),
        ],
        child: const MaterialApp(
          home: Scaffold(body: ChatPage(coupleId: coupleId)),
        ),
      ),
    );

    await _pickSinglePhoto(tester);
    await tester.tap(find.widgetWithText(FilledButton, '이미지 전송'));
    await tester.pump();
    expect(find.text('이미지 업로드 중...'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    completer.complete();
    await tester.pumpAndSettle();

    expect(observedCancellation, isTrue);
    expect(find.byKey(const Key('pending-image-thumbnail')), findsNothing);
  });

  testWidgets('답장은 원문 ID를 구조화해 전송하고 입력창에는 원문을 삽입하지 않는다', (tester) async {
    final original = ChatMessage(
      id: 77,
      coupleId: coupleId,
      senderId: 'user-2',
      body: '우리가 처음 간 곳 기억나?',
      imagePath: null,
      createdAt: DateTime(2026, 7, 12, 9),
      heartCount: 0,
      isHeartedByMe: false,
    );
    int? sentReplyId;
    String? sentText;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatWatchMessagesProvider.overrideWithValue(
            (_) => Stream<List<ChatMessage>>.value([original]),
          ),
          chatCurrentUserIdProvider.overrideWithValue('user-1'),
          chatSendReplyTextProvider.overrideWithValue(({
            required String coupleId,
            required String text,
            int? replyToMessageId,
          }) async {
            sentReplyId = replyToMessageId;
            sentText = text;
          }),
        ],
        child: const MaterialApp(
          home: Scaffold(body: ChatPage(coupleId: coupleId)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.text('우리가 처음 간 곳 기억나?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('답장'));
    await tester.pumpAndSettle();
    expect(find.text('답장하기'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );

    await tester.enterText(find.byType(TextField), '응, 다시 가자!');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    expect(sentReplyId, 77);
    expect(sentText, '응, 다시 가자!');
  });

  testWidgets('내 메시지에 상대 읽음 마커를 기준으로 전송됨과 읽음을 표시한다', (tester) async {
    final messages = [
      ChatMessage(
        id: 41,
        coupleId: coupleId,
        senderId: 'user-1',
        body: '읽은 메시지',
        imagePath: null,
        createdAt: DateTime(2026, 7, 12, 9),
        heartCount: 0,
        isHeartedByMe: false,
      ),
      ChatMessage(
        id: 42,
        coupleId: coupleId,
        senderId: 'user-1',
        body: '아직 안 읽은 메시지',
        imagePath: null,
        createdAt: DateTime(2026, 7, 12, 9, 1),
        heartCount: 0,
        isHeartedByMe: false,
      ),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatWatchMessagesProvider.overrideWithValue(
            (_) => Stream<List<ChatMessage>>.value(messages),
          ),
          chatCurrentUserIdProvider.overrideWithValue('user-1'),
          chatPartnerReadMarkerProvider.overrideWith(
            (ref, coupleId) => Stream.value(
              ChatReadMarker(
                lastReadMessageId: 41,
                lastReadAt: DateTime(2026, 7, 12, 9),
              ),
            ),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: ChatPage(coupleId: coupleId)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('읽음'), findsOneWidget);
    expect(find.text('전송됨'), findsOneWidget);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
  });

  testWidgets('같은 분에 연속된 다중 이미지를 2열 모자이크 한 묶음으로 표시한다', (tester) async {
    final messages = [
      for (var id = 1; id <= 3; id++)
        ChatMessage(
          id: id,
          coupleId: coupleId,
          senderId: 'user-1',
          body: null,
          imagePath: 'photo-$id.jpg',
          createdAt: DateTime(2026, 7, 12, 9, 1, id),
          heartCount: 0,
          isHeartedByMe: false,
        ),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatWatchMessagesProvider.overrideWithValue(
            (_) => Stream<List<ChatMessage>>.value(messages),
          ),
          chatCurrentUserIdProvider.overrideWithValue('user-1'),
          chatResolveImageUrlProvider.overrideWithValue(
            (path) async => 'https://example.invalid/$path',
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: ChatPage(coupleId: coupleId)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final semantics = tester.ensureSemantics();

    expect(
      find.byKey(const ValueKey<String>('chat-image-mosaic-1')),
      findsOneWidget,
    );
    expect(find.byType(Image), findsNWidgets(3));
    expect(find.bySemanticsLabel('사진 크게 보기'), findsNWidgets(3));
    for (final messageId in const [1, 2, 3]) {
      final node = tester.getSemantics(
        find.byKey(ValueKey<String>('chat-image-open-$messageId')),
      );
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );
    }
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
    semantics.dispose();
  });

  testWidgets('채팅 최초 로딩은 스켈레톤, 스트림 오류는 재시도 버튼을 표시한다', (tester) async {
    final controller = StreamController<List<ChatMessage>>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatWatchMessagesProvider.overrideWithValue(
            (_) => controller.stream,
          ),
          chatCurrentUserIdProvider.overrideWithValue('user-1'),
        ],
        child: const MaterialApp(
          home: Scaffold(body: ChatPage(coupleId: coupleId)),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('chat-loading-skeleton')), findsOneWidget);
    await controller.close();

    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          chatWatchMessagesProvider.overrideWithValue(
            (_) => Stream<List<ChatMessage>>.error(Exception('offline')),
          ),
          chatCurrentUserIdProvider.overrideWithValue('user-1'),
        ],
        child: const MaterialApp(
          home: Scaffold(body: ChatPage(coupleId: coupleId)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, '다시 시도'), findsOneWidget);
  });

  testWidgets('내 읽음 remote 실패 후 같은 메시지를 백오프로 다시 동기화한다', (tester) async {
    final controller = StreamController<List<ChatMessage>>();
    final markedIds = <int>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatWatchMessagesProvider.overrideWithValue((_) => controller.stream),
          chatCurrentUserIdProvider.overrideWithValue('user-1'),
          chatMarkReadProvider.overrideWithValue(({
            required coupleId,
            required lastReadMessageId,
            required lastReadAt,
          }) async {
            markedIds.add(lastReadMessageId);
            if (markedIds.length == 1) throw StateError('offline');
          }),
        ],
        child: const MaterialApp(
          home: Scaffold(body: ChatPage(coupleId: coupleId)),
        ),
      ),
    );
    await tester.pump();
    controller.add([
      ChatMessage(
        id: 51,
        coupleId: coupleId,
        senderId: 'user-2',
        body: '다시 동기화해 줘',
        imagePath: null,
        createdAt: DateTime(2026, 7, 12, 10),
        heartCount: 0,
        isHeartedByMe: false,
      ),
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(markedIds, [51]);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(markedIds, [51, 51]);

    await controller.close();
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
  });

  testWidgets('읽음 실패 뒤 더 최신 메시지 이벤트가 오면 즉시 최신 ID로 동기화한다', (tester) async {
    final controller = StreamController<List<ChatMessage>>();
    final markedIds = <int>[];
    ChatMessage partnerMessage(int id) => ChatMessage(
          id: id,
          coupleId: coupleId,
          senderId: 'user-2',
          body: '메시지 $id',
          imagePath: null,
          createdAt: DateTime(2026, 7, 12, 10, id),
          heartCount: 0,
          isHeartedByMe: false,
        );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatWatchMessagesProvider.overrideWithValue((_) => controller.stream),
          chatCurrentUserIdProvider.overrideWithValue('user-1'),
          chatMarkReadProvider.overrideWithValue(({
            required coupleId,
            required lastReadMessageId,
            required lastReadAt,
          }) async {
            markedIds.add(lastReadMessageId);
            if (markedIds.length == 1) throw StateError('offline');
          }),
        ],
        child: const MaterialApp(
          home: Scaffold(body: ChatPage(coupleId: coupleId)),
        ),
      ),
    );
    await tester.pump();
    controller.add([partnerMessage(61)]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(markedIds, [61]);

    controller.add([partnerMessage(61), partnerMessage(62)]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(markedIds, [61, 62]);

    await controller.close();
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
  });
}
