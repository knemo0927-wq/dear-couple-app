import 'package:couple_chat_app/src/features/anniversary/data/anniversary_repository.dart';
import 'package:couple_chat_app/src/features/anniversary/data/anniversary_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildUpcomingAnniversaryTimeline', () {
    test('자동 항목과 사용자 항목을 날짜순으로 안정 병합한다', () {
      final timeline = buildUpcomingAnniversaryTimeline(
        relationshipStart: DateTime(2025, 1, 1),
        now: DateTime(2025, 3, 1, 22),
        limit: 6,
        customItems: [
          _item(
            id: 'trip',
            title: '첫 여행',
            eventDate: DateTime(2025, 3, 15),
            createdAt: DateTime(2025, 2, 1),
          ),
          _item(
            id: 'same-day',
            title: '같은 날의 약속',
            eventDate: DateTime(2025, 4, 10),
            createdAt: DateTime(2025, 2, 2),
          ),
        ],
      );

      expect(
        timeline.map((entry) => entry.title),
        ['첫 여행', '100일', '같은 날의 약속', '200일', '300일', '1주년'],
      );
      expect(timeline[1].eventDate, timeline[2].eventDate);
      expect(timeline[1].kind, AnniversaryTimelineKind.hundredDay);
      expect(timeline[2].kind, AnniversaryTimelineKind.custom);
      expect(timeline.map((entry) => entry.stableId).toSet(), hasLength(6));
    });

    test('같은 날짜의 100일과 주년을 둘 다 보존한다', () {
      final start = DateTime(2000, 1, 1);
      final hundredDate = DateTime(2095, 1, 1);
      final timeline = buildUpcomingAnniversaryTimeline(
        relationshipStart: start,
        now: hundredDate,
        limit: 4,
        customItems: const [],
      );

      final sameDate = timeline
          .where((entry) => entry.eventDate == hundredDate)
          .toList(growable: false);
      expect(sameDate, hasLength(2));
      expect(
        sameDate.map((entry) => entry.kind),
        [AnniversaryTimelineKind.hundredDay, AnniversaryTimelineKind.yearly],
      );
    });

    test('과거 반복 항목은 다음 연도로 이동하고 과거 단발 항목은 숨긴다', () {
      final timeline = buildUpcomingAnniversaryTimeline(
        relationshipStart: null,
        now: DateTime(2026, 7, 12, 18),
        limit: 10,
        customItems: [
          _item(
            id: 'birthday',
            title: '생일',
            eventDate: DateTime(2020, 7, 12),
            repeat: AnniversaryRepeat.yearly,
          ),
          _item(
            id: 'past-once',
            title: '지난 공연',
            eventDate: DateTime(2020, 7, 11),
          ),
          _item(
            id: 'future',
            title: '다음 여행',
            eventDate: DateTime(2026, 8, 1),
          ),
        ],
      );

      expect(timeline.map((entry) => entry.title), ['생일', '다음 여행']);
      expect(timeline.first.eventDate, DateTime(2026, 7, 12));
      expect(timeline.first.customItem?.repeat, AnniversaryRepeat.yearly);
    });

    test('2월 29일 반복 항목은 평년에 2월 말로 보정한다', () {
      final occurrence = nextCustomAnniversaryOccurrence(
        _item(
          id: 'leap',
          title: '윤일의 약속',
          eventDate: DateTime(2024, 2, 29),
          repeat: AnniversaryRepeat.yearly,
        ),
        today: DateTime(2025, 1, 1),
      );

      expect(occurrence, DateTime(2025, 2, 28));
    });
  });

  group('normalizeAnniversaryRows', () {
    test('실시간 중복 행은 최신 버전 한 건만 남기고 안정 정렬한다', () {
      final rows = [
        _row(
          id: 'later',
          title: '나중',
          eventDate: '2026-09-01',
          createdAt: '2026-01-01T00:00:00Z',
        ),
        _row(
          id: 'same',
          title: '수정 전',
          eventDate: '2026-08-01',
          createdAt: '2026-01-02T00:00:00Z',
          updatedAt: '2026-01-02T00:00:00Z',
        ),
        _row(
          id: 'same',
          title: '수정 후',
          eventDate: '2026-07-20',
          createdAt: '2026-01-02T00:00:00Z',
          updatedAt: '2026-02-01T00:00:00Z',
        ),
      ];

      final normalized = normalizeAnniversaryRows(rows);

      expect(normalized, hasLength(2));
      expect(normalized.map((item) => item.title), ['수정 후', '나중']);
      expect(normalized.first.reminderEnabled, isTrue);
      expect(normalized.first.reminderHour, 9);
    });
  });
}

AnniversaryItem _item({
  required String id,
  required String title,
  required DateTime eventDate,
  DateTime? createdAt,
  AnniversaryRepeat repeat = AnniversaryRepeat.none,
}) {
  return AnniversaryItem(
    id: id,
    coupleId: 'couple-1',
    title: title,
    eventDate: eventDate,
    createdAt: createdAt ?? DateTime(2026, 1, 1),
    repeat: repeat,
  );
}

Map<String, dynamic> _row({
  required String id,
  required String title,
  required String eventDate,
  required String createdAt,
  String? updatedAt,
}) {
  return {
    'id': id,
    'couple_id': 'couple-1',
    'title': title,
    'event_date': eventDate,
    'created_at': createdAt,
    if (updatedAt != null) 'updated_at': updatedAt,
  };
}
