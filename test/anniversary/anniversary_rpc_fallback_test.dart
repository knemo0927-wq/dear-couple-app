import 'dart:io';

import 'package:couple_chat_app/src/features/anniversary/data/anniversary_providers.dart';
import 'package:couple_chat_app/src/features/anniversary/data/anniversary_repository.dart';
import 'package:couple_chat_app/src/features/settings/data/couple_prefs_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('anniversary timeline RPC compatibility fallback', () {
    test('PGRST202 falls back with SQL-compatible cursor pagination', () async {
      final today = anniversaryDateOnly(DateTime.now());
      final repository = _ThrowingAnniversaryRepository(
        const PostgrestException(
          message: 'Could not find the function in the schema cache',
          code: 'PGRST202',
        ),
      );
      final customItems = [
        _customItem(
          id: 'custom-a',
          title: '오늘의 약속',
          eventDate: today,
        ),
        _customItem(
          id: 'custom-b',
          title: '내일의 약속',
          eventDate: today.add(const Duration(days: 1)),
        ),
      ];
      final container = ProviderContainer(
        overrides: [
          anniversaryRepositoryProvider.overrideWithValue(repository),
          anniversaryDateProvider.overrideWith(
            (ref) => Stream.value(today.subtract(const Duration(days: 99))),
          ),
          anniversaryItemsProvider.overrideWith(
            (ref, coupleId) => Stream.value(customItems),
          ),
        ],
      );
      addTearDown(container.dispose);

      final fetch = container.read(fetchAnniversaryTimelinePageProvider);
      final first = await fetch(coupleId: 'couple-1', pageSize: 2);
      final second = await fetch(
        coupleId: 'couple-1',
        cursor: first.nextCursor,
        pageSize: 2,
      );

      expect(
        first.items.map((item) => item.stableId),
        ['custom:custom-a', 'days:100'],
      );
      expect(
        second.items.map((item) => item.stableId),
        ['custom:custom-b', 'days:200'],
      );
      expect(first.hasMore, isTrue);
      expect(first.nextCursor?.stableId, 'days:100');
      expect(repository.fetchCalls, 2);

      final combinedIds = [
        ...first.items.map((item) => item.stableId),
        ...second.items.map((item) => item.stableId),
      ];
      expect(combinedIds.toSet(), hasLength(combinedIds.length));
    });

    test('undefined_function 42883 also uses the compatibility page', () async {
      final today = anniversaryDateOnly(DateTime.now());
      final repository = _ThrowingAnniversaryRepository(
        const PostgrestException(
          message: 'function public.get_upcoming_anniversary_timeline missing',
          code: '42883',
        ),
      );
      final container = ProviderContainer(
        overrides: [
          anniversaryRepositoryProvider.overrideWithValue(repository),
          anniversaryDateProvider.overrideWith((ref) => Stream.value(null)),
          anniversaryItemsProvider.overrideWith(
            (ref, coupleId) => Stream.value([
              _customItem(
                id: 'custom-only',
                title: '커스텀 기념일',
                eventDate: today,
              ),
            ]),
          ),
        ],
      );
      addTearDown(container.dispose);

      final page = await container.read(fetchAnniversaryTimelinePageProvider)(
        coupleId: 'couple-1',
      );

      expect(page.items.map((item) => item.stableId), ['custom:custom-only']);
      expect(page.hasMore, isFalse);
    });

    test('RLS and connectivity failures are rethrown without fallback',
        () async {
      final errors = <Object>[
        const PostgrestException(
          message: 'permission denied',
          code: '42501',
        ),
        const SocketException('network unavailable'),
      ];

      for (final error in errors) {
        var fallbackRead = false;
        final container = ProviderContainer(
          overrides: [
            anniversaryRepositoryProvider.overrideWithValue(
              _ThrowingAnniversaryRepository(error),
            ),
            anniversaryDateProvider.overrideWith((ref) {
              fallbackRead = true;
              return Stream.value(null);
            }),
            anniversaryItemsProvider.overrideWith((ref, coupleId) {
              fallbackRead = true;
              return Stream.value(const <AnniversaryItem>[]);
            }),
          ],
        );

        await expectLater(
          container.read(fetchAnniversaryTimelinePageProvider)(
            coupleId: 'couple-1',
          ),
          throwsA(same(error)),
        );
        expect(fallbackRead, isFalse);
        container.dispose();
      }
    });
  });
}

AnniversaryItem _customItem({
  required String id,
  required String title,
  required DateTime eventDate,
}) {
  return AnniversaryItem(
    id: id,
    coupleId: 'couple-1',
    title: title,
    eventDate: eventDate,
    createdAt: DateTime(2026, 1, 1),
  );
}

class _ThrowingAnniversaryRepository extends AnniversaryRepository {
  _ThrowingAnniversaryRepository(this.error)
      : super(
          client: SupabaseClient(
            'http://localhost:54321',
            'test-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
        );

  final Object error;
  int fetchCalls = 0;

  @override
  Future<AnniversaryTimelinePage> fetchTimelinePage({
    required String coupleId,
    AnniversaryTimelineCursor? cursor,
    int pageSize = 15,
    DateTime? today,
  }) async {
    fetchCalls += 1;
    throw error;
  }
}
