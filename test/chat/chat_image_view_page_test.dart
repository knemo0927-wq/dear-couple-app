import 'dart:typed_data';

import 'package:couple_chat_app/src/features/chat/presentation/chat_image_actions.dart';
import 'package:couple_chat_app/src/features/chat/presentation/chat_image_view_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget imageApp({
  required ChatFetchImageBytes fetch,
  required ChatSaveImage save,
  required ChatShareImage share,
  double textScale = 1,
}) {
  return ProviderScope(
    overrides: [
      chatFetchImageBytesProvider.overrideWithValue(fetch),
      chatSaveImageProvider.overrideWithValue(save),
      chatShareImageProvider.overrideWithValue(share),
    ],
    child: MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: const ChatImageViewPage(
          imageUrl: 'https://example.invalid/photo.png',
          heroTag: 'photo',
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('이미지 상세에서 바이트를 내려받아 실제 저장·공유 동작에 전달한다', (tester) async {
    var fetchCount = 0;
    Uint8List? savedBytes;
    Uint8List? sharedBytes;
    String? sharedFilename;
    await tester.pumpWidget(
      imageApp(
        fetch: (_) async {
          fetchCount++;
          return Uint8List.fromList([1, 2, 3, 4]);
        },
        save: ({required bytes, required name}) async {
          savedBytes = bytes;
          expect(name, startsWith('dear_'));
          return ChatImageSaveResult.saved;
        },
        share: ({
          required bytes,
          required filename,
          required mimeType,
          sharePositionOrigin,
        }) async {
          sharedBytes = bytes;
          sharedFilename = filename;
          expect(mimeType, 'image/png');
          expect(sharePositionOrigin, isNotNull);
        },
      ),
    );

    await tester.tap(find.byKey(const Key('chat-image-save')));
    await tester.pumpAndSettle();
    expect(savedBytes, Uint8List.fromList([1, 2, 3, 4]));
    expect(find.text('사진 보관함에 저장했어요.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('chat-image-share')));
    await tester.pumpAndSettle();
    expect(sharedBytes, Uint8List.fromList([1, 2, 3, 4]));
    expect(sharedFilename, endsWith('.png'));
    expect(fetchCount, 1, reason: '저장 뒤 공유할 때 다운로드 바이트를 재사용해야 한다.');
  });

  testWidgets('권한 거부를 명확히 안내하고 큰 글자에서도 버튼이 오버플로되지 않는다', (tester) async {
    await tester.pumpWidget(
      imageApp(
        textScale: 2,
        fetch: (_) async => Uint8List.fromList([1]),
        save: ({required bytes, required name}) async =>
            ChatImageSaveResult.permissionDenied,
        share: ({
          required bytes,
          required filename,
          required mimeType,
          sharePositionOrigin,
        }) async {},
      ),
    );
    await tester.tap(find.byKey(const Key('chat-image-save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('기기 설정에서 권한을 허용'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
