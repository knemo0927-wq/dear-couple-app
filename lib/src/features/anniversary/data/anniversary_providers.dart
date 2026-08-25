import 'dart:async';

import 'package:couple_chat_app/src/features/anniversary/data/anniversary_repository.dart';
import 'package:couple_chat_app/src/features/anniversary/data/anniversary_timeline.dart';
import 'package:couple_chat_app/src/features/settings/data/couple_prefs_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

export 'package:couple_chat_app/src/features/anniversary/data/anniversary_models.dart';
export 'package:couple_chat_app/src/features/anniversary/data/anniversary_timeline.dart';

typedef WatchAnniversariesAction = Stream<List<AnniversaryItem>> Function(
  String coupleId,
);
typedef AddAnniversaryAction = Future<void> Function({
  required String coupleId,
  required String title,
  required DateTime eventDate,
  required AnniversaryRepeat repeat,
  required bool reminderEnabled,
  required int reminderDaysBefore,
  required int reminderHour,
  String? note,
  String? linkedAlbumId,
});
typedef UpdateAnniversaryAction = Future<void> Function({
  required String id,
  required String title,
  required DateTime eventDate,
  required AnniversaryRepeat repeat,
  required bool reminderEnabled,
  required int reminderDaysBefore,
  required int reminderHour,
  String? note,
  String? linkedAlbumId,
});
typedef RemoveAnniversaryAction = Future<void> Function(String id);
typedef FetchAnniversaryTimelinePageAction = Future<AnniversaryTimelinePage>
    Function({
  required String coupleId,
  AnniversaryTimelineCursor? cursor,
  int pageSize,
});

final anniversaryRepositoryProvider = Provider<AnniversaryRepository>(
  (ref) => AnniversaryRepository(),
);

final watchAnniversariesProvider = Provider<WatchAnniversariesAction>((ref) {
  return ref.watch(anniversaryRepositoryProvider).watchAnniversaries;
});

final anniversaryItemsProvider =
    StreamProvider.family<List<AnniversaryItem>, String>((ref, coupleId) {
  return ref.watch(watchAnniversariesProvider)(coupleId);
});

final addAnniversaryProvider = Provider<AddAnniversaryAction>((ref) {
  return ({
    required coupleId,
    required title,
    required eventDate,
    required repeat,
    required reminderEnabled,
    required reminderDaysBefore,
    required reminderHour,
    note,
    linkedAlbumId,
  }) {
    return ref.read(anniversaryRepositoryProvider).addAnniversary(
          coupleId: coupleId,
          title: title,
          eventDate: eventDate,
          repeat: repeat,
          reminderEnabled: reminderEnabled,
          reminderDaysBefore: reminderDaysBefore,
          reminderHour: reminderHour,
          note: note,
          linkedAlbumId: linkedAlbumId,
        );
  };
});

final updateAnniversaryProvider = Provider<UpdateAnniversaryAction>((ref) {
  return ({
    required id,
    required title,
    required eventDate,
    required repeat,
    required reminderEnabled,
    required reminderDaysBefore,
    required reminderHour,
    note,
    linkedAlbumId,
  }) {
    return ref.read(anniversaryRepositoryProvider).updateAnniversary(
          id: id,
          title: title,
          eventDate: eventDate,
          repeat: repeat,
          reminderEnabled: reminderEnabled,
          reminderDaysBefore: reminderDaysBefore,
          reminderHour: reminderHour,
          note: note,
          linkedAlbumId: linkedAlbumId,
        );
  };
});

final removeAnniversaryProvider = Provider<RemoveAnniversaryAction>((ref) {
  return ref.read(anniversaryRepositoryProvider).removeAnniversary;
});

final fetchAnniversaryTimelinePageProvider =
    Provider<FetchAnniversaryTimelinePageAction>((ref) {
  final repository = ref.watch(anniversaryRepositoryProvider);
  return ({required coupleId, cursor, pageSize = 15}) async {
    try {
      return await repository.fetchTimelinePage(
        coupleId: coupleId,
        cursor: cursor,
        pageSize: pageSize,
      );
    } on PostgrestException catch (error) {
      if (!_isMissingAnniversaryTimelineRpc(error)) rethrow;
    }

    // The dashboard already reads these two RLS-scoped streams. Reuse the
    // same data when an older deployment does not yet expose the bounded RPC,
    // rather than turning a schema rollout mismatch into an unusable screen.
    // Other PostgREST and connectivity errors are deliberately not masked.
    final relationshipStartFuture = ref.read(anniversaryDateProvider.future);
    final customItemsFuture =
        ref.read(anniversaryItemsProvider(coupleId).future);
    final relationshipStart = await relationshipStartFuture;
    final customItems = await customItemsFuture;
    return _buildLocalAnniversaryTimelinePage(
      relationshipStart: relationshipStart,
      customItems: customItems,
      cursor: cursor,
      pageSize: pageSize,
    );
  };
});

bool _isMissingAnniversaryTimelineRpc(PostgrestException error) {
  return error.code == 'PGRST202' || error.code == '42883';
}

/// Compatibility implementation of `get_upcoming_anniversary_timeline`.
///
/// Stable IDs, generation limits, ordering, and cursor comparison intentionally
/// mirror `202607120007_anniversary_timeline_cursor.sql`, so a schema rollout
/// can switch between the local and server paths without skipping or repeating
/// entries.
AnniversaryTimelinePage _buildLocalAnniversaryTimelinePage({
  required DateTime? relationshipStart,
  required Iterable<AnniversaryItem> customItems,
  required AnniversaryTimelineCursor? cursor,
  required int pageSize,
  DateTime? today,
}) {
  final targetToday = anniversaryDateOnly(today ?? DateTime.now());
  final candidates = <AnniversaryTimelineEntry>[];

  if (relationshipStart != null) {
    final start = anniversaryDateOnly(relationshipStart);
    for (var milestone = 100; milestone <= 36500; milestone += 100) {
      final eventDate = start.add(Duration(days: milestone - 1));
      if (eventDate.isBefore(targetToday)) continue;
      candidates.add(
        AnniversaryTimelineEntry(
          stableId: 'days:$milestone',
          title: '$milestone일',
          eventDate: eventDate,
          kind: AnniversaryTimelineKind.hundredDay,
          dayCount: milestone,
        ),
      );
    }

    for (var milestone = 1; milestone <= 100; milestone += 1) {
      final eventDate = anniversaryDateForYear(start, milestone);
      if (eventDate.isBefore(targetToday)) continue;
      candidates.add(
        AnniversaryTimelineEntry(
          stableId: 'years:$milestone',
          title: '$milestone주년',
          eventDate: eventDate,
          kind: AnniversaryTimelineKind.yearly,
          yearCount: milestone,
        ),
      );
    }
  }

  final latestCustomItems = <String, AnniversaryItem>{};
  for (final item in customItems) {
    final previous = latestCustomItems[item.id];
    final itemVersion = item.updatedAt ?? item.createdAt;
    final previousVersion = previous?.updatedAt ?? previous?.createdAt;
    if (previous == null || !itemVersion.isBefore(previousVersion!)) {
      latestCustomItems[item.id] = item;
    }
  }
  for (final item in latestCustomItems.values) {
    final eventDate = nextCustomAnniversaryOccurrence(
      item,
      today: targetToday,
    );
    if (eventDate == null) continue;
    candidates.add(
      AnniversaryTimelineEntry(
        stableId: 'custom:${item.id}',
        title: item.title,
        eventDate: eventDate,
        kind: AnniversaryTimelineKind.custom,
        customItem: item,
      ),
    );
  }

  candidates.sort(_compareTimelineCursorValues);
  final afterCursor = cursor == null
      ? candidates
      : candidates.where((item) {
          final dateCompare = item.eventDate.compareTo(cursor.eventDate);
          return dateCompare > 0 ||
              (dateCompare == 0 &&
                  item.stableId.compareTo(cursor.stableId) > 0);
        }).toList(growable: false);
  final boundedPageSize = pageSize.clamp(1, 50);
  final hasMore = afterCursor.length > boundedPageSize;
  final items = afterCursor.take(boundedPageSize).toList(growable: false);
  final last = items.isEmpty ? null : items.last;
  return AnniversaryTimelinePage(
    items: List<AnniversaryTimelineEntry>.unmodifiable(items),
    nextCursor: last == null
        ? null
        : AnniversaryTimelineCursor(
            eventDate: last.eventDate,
            stableId: last.stableId,
          ),
    hasMore: hasMore,
  );
}

int _compareTimelineCursorValues(
  AnniversaryTimelineEntry left,
  AnniversaryTimelineEntry right,
) {
  final dateCompare = left.eventDate.compareTo(right.eventDate);
  return dateCompare != 0
      ? dateCompare
      : left.stableId.compareTo(right.stableId);
}

class AnniversaryTimelineFeedState {
  const AnniversaryTimelineFeedState({
    this.items = const <AnniversaryTimelineEntry>[],
    this.nextCursor,
    this.hasMore = true,
    this.isLoadingInitial = true,
    this.isLoadingMore = false,
    this.error,
  });

  final List<AnniversaryTimelineEntry> items;
  final AnniversaryTimelineCursor? nextCursor;
  final bool hasMore;
  final bool isLoadingInitial;
  final bool isLoadingMore;
  final Object? error;
}

class AnniversaryTimelineFeedController
    extends StateNotifier<AnniversaryTimelineFeedState> {
  AnniversaryTimelineFeedController({
    required String coupleId,
    required FetchAnniversaryTimelinePageAction fetchPage,
  })  : _coupleId = coupleId,
        _fetchPage = fetchPage,
        super(const AnniversaryTimelineFeedState()) {
    unawaited(refresh());
  }

  final String _coupleId;
  final FetchAnniversaryTimelinePageAction _fetchPage;
  int _generation = 0;

  Future<void> refresh() async {
    final generation = ++_generation;
    state = AnniversaryTimelineFeedState(
      items: state.items,
      isLoadingInitial: state.items.isEmpty,
    );
    try {
      final page = await _fetchPage(coupleId: _coupleId, pageSize: 15);
      if (!mounted || generation != _generation) return;
      state = AnniversaryTimelineFeedState(
        items: page.items,
        nextCursor: page.nextCursor,
        hasMore: page.hasMore,
        isLoadingInitial: false,
      );
    } catch (error) {
      if (!mounted || generation != _generation) return;
      state = AnniversaryTimelineFeedState(
        items: state.items,
        hasMore: state.hasMore,
        isLoadingInitial: false,
        error: error,
      );
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingInitial || state.isLoadingMore || !state.hasMore) return;
    final cursor = state.nextCursor;
    if (cursor == null) return;
    final generation = _generation;
    state = AnniversaryTimelineFeedState(
      items: state.items,
      nextCursor: state.nextCursor,
      hasMore: state.hasMore,
      isLoadingInitial: false,
      isLoadingMore: true,
    );
    try {
      final page = await _fetchPage(
        coupleId: _coupleId,
        cursor: cursor,
        pageSize: 15,
      );
      if (!mounted || generation != _generation) return;
      final byId = <String, AnniversaryTimelineEntry>{
        for (final item in state.items) item.stableId: item,
        for (final item in page.items) item.stableId: item,
      };
      final merged = byId.values.toList(growable: false)
        ..sort((a, b) {
          final date = a.eventDate.compareTo(b.eventDate);
          return date != 0 ? date : a.stableId.compareTo(b.stableId);
        });
      state = AnniversaryTimelineFeedState(
        items: merged,
        nextCursor: page.nextCursor,
        hasMore: page.hasMore,
        isLoadingInitial: false,
      );
    } catch (error) {
      if (!mounted || generation != _generation) return;
      state = AnniversaryTimelineFeedState(
        items: state.items,
        nextCursor: state.nextCursor,
        hasMore: state.hasMore,
        isLoadingInitial: false,
        error: error,
      );
    }
  }
}

final anniversaryTimelineFeedProvider = StateNotifierProvider.autoDispose
    .family<AnniversaryTimelineFeedController, AnniversaryTimelineFeedState,
        String>((ref, coupleId) {
  return AnniversaryTimelineFeedController(
    coupleId: coupleId,
    fetchPage: ref.watch(fetchAnniversaryTimelinePageProvider),
  );
});

class AnniversaryTimelineQuery {
  const AnniversaryTimelineQuery({
    required this.coupleId,
    required this.limit,
    this.now,
  });

  final String coupleId;
  final int limit;

  /// Intended for deterministic previews and tests. Production callers omit it.
  final DateTime? now;

  @override
  bool operator ==(Object other) {
    return other is AnniversaryTimelineQuery &&
        other.coupleId == coupleId &&
        other.limit == limit &&
        other.now == now;
  }

  @override
  int get hashCode => Object.hash(coupleId, limit, now);
}

final upcomingAnniversaryTimelineProvider = Provider.family<
    AsyncValue<List<AnniversaryTimelineEntry>>,
    AnniversaryTimelineQuery>((ref, query) {
  final relationshipStart = ref.watch(anniversaryDateProvider);
  final customItems = ref.watch(anniversaryItemsProvider(query.coupleId));

  if (relationshipStart.hasError) {
    return AsyncValue.error(
      relationshipStart.error!,
      relationshipStart.stackTrace ?? StackTrace.current,
    );
  }
  if (customItems.hasError) {
    return AsyncValue.error(
      customItems.error!,
      customItems.stackTrace ?? StackTrace.current,
    );
  }
  if (relationshipStart.isLoading || customItems.isLoading) {
    return const AsyncValue.loading();
  }

  return AsyncValue.data(
    buildUpcomingAnniversaryTimeline(
      relationshipStart: relationshipStart.valueOrNull,
      customItems: customItems.valueOrNull ?? const <AnniversaryItem>[],
      limit: query.limit,
      now: query.now,
    ),
  );
});

final latestAnniversaryActivityAtProvider =
    StreamProvider.family<DateTime?, String>((ref, coupleId) {
  return ref.watch(watchAnniversariesProvider)(coupleId).map((items) {
    DateTime? latest;
    for (final item in items) {
      final activityAt = item.updatedAt ?? item.createdAt;
      if (latest == null || activityAt.isAfter(latest)) {
        latest = activityAt;
      }
    }
    return latest;
  });
});
