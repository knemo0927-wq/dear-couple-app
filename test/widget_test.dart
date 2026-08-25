import 'package:couple_chat_app/src/app_root.dart';
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
}
