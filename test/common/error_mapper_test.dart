import 'package:flutter_test/flutter_test.dart';
import 'package:couple_chat_app/src/common/error_mapper.dart';

void main() {
  test('AUTH_REQUIRED 에러를 친화 메시지로 변환한다', () {
    expect(
      toFriendlyErrorMessage(
          'AuthException(message: AUTH_REQUIRED, statusCode: 401)'),
      '로그인이 필요해요. 다시 로그인해 주세요.',
    );
  });

  test('네트워크 오류를 친화 메시지로 변환한다', () {
    expect(
      toFriendlyErrorMessage('SocketException: Failed host lookup'),
      '네트워크 연결이 불안정해요. 인터넷 연결을 확인해 주세요.',
    );
  });

  test('알 수 없는 에러는 기본 메시지로 변환한다', () {
    expect(
      toFriendlyErrorMessage('Random unknown error'),
      '요청 처리 중 문제가 발생했어요. 잠시 후 다시 시도해 주세요.',
    );
  });
}
