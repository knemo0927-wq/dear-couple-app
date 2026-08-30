import 'dart:convert';

import 'package:couple_chat_app/src/features/chat/data/chat_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('한국어 검색은 reply 컬럼 누락 때 구형 select로 한 번만 재조회한다', () async {
    final requests = <http.Request>[];
    var requestCount = 0;
    final client = _supabaseClient(
      MockClient((request) async {
        requests.add(request);
        requestCount += 1;
        if (requestCount == 1) {
          return _jsonResponse(
            400,
            {
              'code': '42703',
              'message': 'column messages.reply_to_message_id does not exist',
              'details': null,
              'hint': null,
            },
            request: request,
          );
        }
        return _jsonResponse(
          200,
          [
            {
              'id': 7,
              'couple_id': 'couple-1',
              'sender_id': 'user-2',
              'body': '젤라와 함께한 여름 여행',
              'image_path': null,
              'created_at': '2026-08-30T02:27:00Z',
            },
          ],
          request: request,
        );
      }),
    );
    addTearDown(client.dispose);

    final messages = await ChatRepository(client: client).searchMessages(
      coupleId: 'couple-1',
      query: '  젤라  ',
    );

    expect(messages, hasLength(1));
    expect(messages.single.body, '젤라와 함께한 여름 여행');
    expect(messages.single.replyToMessageId, isNull);
    expect(requests, hasLength(2));
    expect(
      requests.first.url.queryParameters['select'],
      contains('reply_to_message_id'),
    );
    expect(
      requests.last.url.queryParameters['select'],
      isNot(contains('reply_to_message_id')),
    );
    expect(requests.last.url.queryParameters['body'], 'ilike.%젤라%');
  });

  test('PGRST204도 reply 컬럼을 지목할 때만 호환 재조회를 허용한다', () async {
    final requests = <http.Request>[];
    final client = _supabaseClient(
      MockClient((request) async {
        requests.add(request);
        if (requests.length == 1) {
          return _jsonResponse(
            400,
            {
              'code': 'PGRST204',
              'message': "Could not find the 'reply_to_message_id' column",
              'details': 'Searched the schema cache for public.messages',
              'hint': null,
            },
            request: request,
          );
        }
        return _jsonResponse(200, const [], request: request);
      }),
    );
    addTearDown(client.dispose);

    final messages = await ChatRepository(client: client).searchMessages(
      coupleId: 'couple-1',
      query: '검색어',
    );

    expect(messages, isEmpty);
    expect(requests, hasLength(2));
  });

  test('같은 오류 코드라도 다른 컬럼 오류는 숨기지 않는다', () async {
    final requests = <http.Request>[];
    final client = _supabaseClient(
      MockClient((request) async {
        requests.add(request);
        return _jsonResponse(
          400,
          {
            'code': '42703',
            'message': 'column messages.unrelated_column does not exist',
            'details': null,
            'hint': null,
          },
          request: request,
        );
      }),
    );
    addTearDown(client.dispose);

    await expectLater(
      ChatRepository(client: client).searchMessages(
        coupleId: 'couple-1',
        query: '젤라',
      ),
      throwsA(
        isA<PostgrestException>()
            .having((error) => error.code, 'code', '42703')
            .having(
              (error) => error.message,
              'message',
              contains('unrelated_column'),
            ),
      ),
    );
    expect(requests, hasLength(1));
  });

  test('호환 재조회 실패는 세 번째 요청 없이 원래대로 전달한다', () async {
    final requests = <http.Request>[];
    final client = _supabaseClient(
      MockClient((request) async {
        requests.add(request);
        return _jsonResponse(
          400,
          {
            'code': '42703',
            'message': 'column messages.reply_to_message_id does not exist',
            'details': null,
            'hint': null,
          },
          request: request,
        );
      }),
    );
    addTearDown(client.dispose);

    await expectLater(
      ChatRepository(client: client).searchMessages(
        coupleId: 'couple-1',
        query: '젤라',
      ),
      throwsA(isA<PostgrestException>()),
    );
    expect(requests, hasLength(2));
    expect(
      requests.last.url.queryParameters['select'],
      isNot(contains('reply_to_message_id')),
    );
  });
}

SupabaseClient _supabaseClient(http.Client httpClient) {
  return SupabaseClient(
    'http://localhost:54321',
    'test-key',
    httpClient: httpClient,
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
}

http.Response _jsonResponse(
  int statusCode,
  Object body, {
  required http.BaseRequest request,
}) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    request: request,
    headers: const {'content-type': 'application/json; charset=utf-8'},
  );
}
