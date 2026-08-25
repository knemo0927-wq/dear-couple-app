import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:couple_chat_app/src/common/dear_connection_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('연결이 없으면 기존 콘텐츠 위에 오프라인 배너를 표시한다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectivityResultsProvider.overrideWith(
            (ref) => Stream.value(const [ConnectivityResult.none]),
          ),
        ],
        child: const MaterialApp(
          home: DearConnectionBanner(
            child: Scaffold(body: Text('마지막 콘텐츠')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('마지막 콘텐츠'), findsOneWidget);
    expect(find.text('오프라인 · 마지막으로 불러온 내용을 표시해요'), findsOneWidget);
  });
}
