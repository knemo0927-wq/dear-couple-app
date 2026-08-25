import 'package:flutter_test/flutter_test.dart';
import 'package:couple_chat_app/src/features/chat/presentation/chat_format.dart';

void main() {
  test('같은 날짜 메시지는 날짜 헤더가 필요 없다', () {
    final now = DateTime(2026, 4, 18, 12, 0);
    final previous = DateTime(2026, 4, 18, 9, 0);

    expect(needsDateHeader(now, previous), isFalse);
  });

  test('다른 날짜 메시지는 날짜 헤더가 필요하다', () {
    final now = DateTime(2026, 4, 18, 12, 0);
    final previous = DateTime(2026, 4, 17, 23, 59);

    expect(needsDateHeader(now, previous), isTrue);
  });

  test('오늘 날짜 라벨은 오늘로 표시한다', () {
    final now = DateTime(2026, 4, 18, 12, 0);

    expect(chatDateLabel(now, now: now), '오늘');
  });
}
