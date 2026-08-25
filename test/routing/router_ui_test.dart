import 'package:couple_chat_app/src/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('잘못된 채팅 링크 페이지가 안내 문구를 보여준다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: InvalidChatLinkPage(),
      ),
    );

    expect(find.text('잘못된 채팅 링크'), findsOneWidget);
    expect(find.text('유효하지 않은 채팅 링크예요.'), findsOneWidget);
    expect(find.text('홈으로 이동'), findsOneWidget);
  });
}
