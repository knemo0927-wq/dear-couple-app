import 'dart:async';
import 'dart:typed_data';

import 'package:couple_chat_app/src/common/dear_design.dart';
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
  List<String>? imageUrls,
  int initialIndex = 0,
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
        child: ChatImageViewPage(
          imageUrl: 'https://example.invalid/photo.png',
          heroTag: 'photo',
          imageUrls: imageUrls,
          initialIndex: initialIndex,
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
    expect(
      find.descendant(
        of: find.byType(DearInlineError),
        matching: find.text('다시 시도'),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('저장 중에도 사진을 유지하고 저장·공유 버튼을 함께 잠근다', (tester) async {
    final fetchCompleter = Completer<Uint8List>();
    await tester.pumpWidget(
      imageApp(
        fetch: (_) => fetchCompleter.future,
        save: ({required bytes, required name}) async =>
            ChatImageSaveResult.saved,
        share: ({
          required bytes,
          required filename,
          required mimeType,
          sharePositionOrigin,
        }) async {},
      ),
    );
    final semantics = tester.ensureSemantics();

    await tester.tap(find.byKey(const Key('chat-image-save')));
    await tester.pump();

    expect(find.byType(PageView), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('chat-image-save')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('chat-image-share')))
          .onPressed,
      isNull,
    );
    expect(find.bySemanticsLabel('1번째 사진 저장 중'), findsOneWidget);

    fetchCompleter.complete(Uint8List.fromList([1, 2, 3]));
    await tester.pumpAndSettle();
    semantics.dispose();
  });

  testWidgets('저장 실패 재시도는 내려받은 바이트를 재사용한다', (tester) async {
    var fetchCount = 0;
    var saveCount = 0;
    await tester.pumpWidget(
      imageApp(
        fetch: (_) async {
          fetchCount++;
          return Uint8List.fromList([7, 8, 9]);
        },
        save: ({required bytes, required name}) async {
          saveCount++;
          if (saveCount == 1) throw Exception('temporary save failure');
          return ChatImageSaveResult.saved;
        },
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
    expect(find.text('사진을 저장하지 못했어요.'), findsOneWidget);
    expect(find.byType(PageView), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(DearInlineError),
        matching: find.text('다시 시도'),
      ),
    );
    await tester.pumpAndSettle();

    expect(saveCount, 2);
    expect(fetchCount, 1);
    expect(find.text('사진을 저장하지 못했어요.'), findsNothing);
  });

  testWidgets('저장 중 페이지를 넘겨도 시작한 사진의 번호와 바이트를 사용한다', (tester) async {
    final firstFetch = Completer<Uint8List>();
    Uint8List? savedBytes;
    String? savedName;
    await tester.pumpWidget(
      imageApp(
        imageUrls: const [
          'https://example.invalid/first.png',
          'https://example.invalid/second.png',
        ],
        fetch: (url) {
          if (url.endsWith('first.png')) return firstFetch.future;
          return Future.value(Uint8List.fromList([2]));
        },
        save: ({required bytes, required name}) async {
          savedBytes = bytes;
          savedName = name;
          return ChatImageSaveResult.saved;
        },
        share: ({
          required bytes,
          required filename,
          required mimeType,
          sharePositionOrigin,
        }) async {},
      ),
    );

    await tester.tap(find.byKey(const Key('chat-image-save')));
    await tester.pump();
    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('이미지 보기 2 / 2'), findsOneWidget);

    firstFetch.complete(Uint8List.fromList([1]));
    await tester.pumpAndSettle();

    expect(savedBytes, Uint8List.fromList([1]));
    expect(savedName, endsWith('_1'));
  });

  testWidgets('이미지 로딩 실패는 44pt 재시도와 live 안내를 제공한다', (tester) async {
    await tester.pumpWidget(
      imageApp(
        fetch: (_) async => Uint8List.fromList([1]),
        save: ({required bytes, required name}) async =>
            ChatImageSaveResult.saved,
        share: ({
          required bytes,
          required filename,
          required mimeType,
          sharePositionOrigin,
        }) async {},
      ),
    );
    final semantics = tester.ensureSemantics();
    await tester.pumpAndSettle();

    final retry = find.byKey(const ValueKey<String>('chat-image-retry-0'));
    expect(retry, findsOneWidget);
    expect(tester.getSize(retry).width, greaterThanOrEqualTo(44));
    expect(tester.getSize(retry).height, greaterThanOrEqualTo(44));
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.liveRegion == true &&
            (widget.properties.label ?? '').contains('이미지를 불러오지 못했어요'),
      ),
      findsOneWidget,
    );

    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('chat-image-view-0-1')),
      findsOneWidget,
    );
    semantics.dispose();
  });
}
