import 'package:couple_chat_app/src/features/notifications/data/notification_inbox.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('알림 job을 읽지 않은 상세 알림으로 변환한다', () {
    final item = NotificationInboxItem.fromMap({
      'id': '11111111-1111-4111-8111-111111111111',
      'category': 'game',
      'route': '/omok/invite/invite-1',
      'payload': {
        'title': 'Dear 오목',
        'body': '오목 초대가 도착했어요.',
      },
      'status': 'sent',
      'created_at': '2026-07-12T09:00:00Z',
      'read_at': null,
    });

    expect(item.title, 'Dear 오목');
    expect(item.body, '오목 초대가 도착했어요.');
    expect(item.isUnread, isTrue);
  });

  test('실패·취소 job은 홈 미확인 배지에서 제외한다', () {
    for (final status in ['failed', 'cancelled']) {
      final item = NotificationInboxItem.fromMap({
        'id': '11111111-1111-4111-8111-111111111111',
        'category': 'message',
        'route': '/chat/11111111-1111-4111-8111-111111111111',
        'payload': <String, dynamic>{},
        'status': status,
        'created_at': '2026-07-12T09:00:00Z',
        'read_at': null,
      });
      expect(item.isUnread, isFalse);
    }
  });
}
