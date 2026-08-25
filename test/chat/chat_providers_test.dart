import 'package:couple_chat_app/src/features/chat/data/chat_providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatImageSizeLabel', () {
    test('MB 단위로 표시한다', () {
      expect(formatImageSizeLabel(6 * 1024 * 1024), '6.0 MB');
    });

    test('KB 단위로 표시한다', () {
      expect(formatImageSizeLabel(1200), '1.2 KB');
    });
  });

  group('image size policy', () {
    test('5MB 초과면 경고 대상이다', () {
      expect(isImageSizeWarning(5 * 1024 * 1024 + 1), true);
      expect(isImageSizeWarning(5 * 1024 * 1024), false);
    });

    test('8MB 초과면 전송 차단 대상이다', () {
      expect(isImageTooLarge(8 * 1024 * 1024 + 1), true);
      expect(isImageTooLarge(8 * 1024 * 1024), false);
    });
  });

  group('resolveImageExtension', () {
    test('확장자가 없으면 jpg를 반환한다', () {
      expect(resolveImageExtension('photo'), 'jpg');
    });

    test('파일명이 점으로 끝나면 jpg를 반환한다', () {
      expect(resolveImageExtension('photo.'), 'jpg');
    });

    test('확장자는 소문자로 정규화한다', () {
      expect(resolveImageExtension('photo.PNG'), 'png');
    });
  });

  group('normalizeImageExtension', () {
    test('jpeg은 jpg로 정규화한다', () {
      expect(normalizeImageExtension('jpeg'), 'jpg');
    });

    test('앞에 점이 있어도 제거한다', () {
      expect(normalizeImageExtension('.PNG'), 'png');
    });
  });

  group('isSupportedImageExtension', () {
    test('jpg/png/webp는 허용한다', () {
      expect(isSupportedImageExtension('jpg'), true);
      expect(isSupportedImageExtension('png'), true);
      expect(isSupportedImageExtension('webp'), true);
    });

    test('gif는 허용하지 않는다', () {
      expect(isSupportedImageExtension('gif'), false);
    });
  });
}
