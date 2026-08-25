import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android 앱은 전경 현재 위치 권한을 선언한다', () async {
    final manifest =
        await File('android/app/src/main/AndroidManifest.xml').readAsString();

    expect(manifest, contains('android.permission.ACCESS_COARSE_LOCATION'));
    expect(manifest, contains('android.permission.ACCESS_FINE_LOCATION'));
    expect(manifest, isNot(contains('ACCESS_BACKGROUND_LOCATION')));
  });

  test('iOS 앱은 when-in-use 설명과 always 권한 우회를 선언한다', () async {
    final info = await File('ios/Runner/Info.plist').readAsString();
    final podfile = await File('ios/Podfile').readAsString();

    expect(info, contains('NSLocationWhenInUseUsageDescription'));
    expect(info, contains('여행 지도에서 현재 위치를 찾아'));
    expect(
        info, isNot(contains('NSLocationAlwaysAndWhenInUseUsageDescription')));
    expect(podfile, contains('BYPASS_PERMISSION_LOCATION_ALWAYS=1'));
  });

  test('geolocator 호환 버전이 앱 의존성에 고정되어 있다', () async {
    final pubspec = await File('pubspec.yaml').readAsString();
    expect(pubspec, contains('geolocator: ^13.0.4'));
  });
}
