import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:couple_chat_app/src/features/notifications/data/notification_inbox.dart';
import 'package:couple_chat_app/src/features/notifications/data/notification_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('알림함 repository가 PostgREST 원본 오류 코드를 보존한다', () async {
    final backend = await _ErrorBackend.start(
      code: 'PGRST205',
      message: "Could not find the table 'public.notification_jobs'",
      statusCode: HttpStatus.notFound,
    );
    addTearDown(backend.close);
    final client = backend.client();
    addTearDown(client.dispose);

    final errors = <Object>[];
    final done = Completer<void>();
    final subscription =
        NotificationInboxRepository(client: client).watch('user-1').listen(
              (_) {},
              onError: (Object error) => errors.add(error),
              onDone: done.complete,
            );
    addTearDown(subscription.cancel);
    await done.future.timeout(const Duration(seconds: 5));

    expect(
      errors,
      contains(
        isA<PostgrestException>()
            .having((error) => error.code, 'code', 'PGRST205')
            .having(
              (error) => error.message,
              'message',
              contains('notification_jobs'),
            ),
      ),
    );
  });

  test('알림 설정 repository가 save의 원본 오류 코드를 보존한다', () async {
    final backend = await _ErrorBackend.start(
      code: 'PGRST205',
      message: "Could not find the table 'public.notification_preferences'",
      statusCode: HttpStatus.notFound,
    );
    addTearDown(backend.close);
    final client = backend.client();
    addTearDown(client.dispose);

    await expectLater(
      NotificationPreferencesRepository(client: client).save(
        const NotificationPreferences(userId: 'user-1'),
      ),
      throwsA(
        isA<PostgrestException>()
            .having((error) => error.code, 'code', 'PGRST205')
            .having(
              (error) => error.message,
              'message',
              contains('notification_preferences'),
            ),
      ),
    );
  });
}

class _ErrorBackend {
  _ErrorBackend._(this._server, this._subscription);

  final HttpServer _server;
  final StreamSubscription<HttpRequest> _subscription;

  static Future<_ErrorBackend> start({
    required String code,
    required String message,
    required int statusCode,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((request) async {
      request.response
        ..statusCode = statusCode
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'code': code,
            'message': message,
            'details': null,
            'hint': null,
          }),
        );
      await request.response.close();
    });
    return _ErrorBackend._(server, subscription);
  }

  SupabaseClient client() => SupabaseClient(
        'http://${_server.address.host}:${_server.port}',
        'test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );

  Future<void> close() async {
    await _subscription.cancel();
    await _server.close(force: true);
  }
}
