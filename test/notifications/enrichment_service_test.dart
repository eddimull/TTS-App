import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/core/network/geocoding.dart';
import 'package:tts_bandmate/features/notifications/services/enrichment_service.dart';

class _FakeScheduler implements LocalScheduler {
  final List<({int id, String body, DateTime when})> scheduled = [];
  final List<int> cancelled = [];
  @override
  Future<void> scheduleLocal({
    required int id,
    required String title,
    required String body,
    required DateTime when,
  }) async =>
      scheduled.add((id: id, body: body, when: when));
  @override
  Future<void> cancelLocal(int id) async => cancelled.add(id);
}

EnrichmentInput _input({
  required DateTime now,
  required DateTime firstItem,
  required Duration travel,
  required double meters,
}) =>
    EnrichmentInput(
      notificationId: 42,
      eventTitle: 'Gig',
      venue: 'The Blue Room',
      firstItemTitle: 'Load In',
      firstItem: firstItem,
      now: now,
      origin: const GeoPoint(30, -91),
      travel: travel,
      metersToVenue: meters,
    );

void main() {
  late _FakeScheduler scheduler;
  setUp(() => scheduler = _FakeScheduler());

  test('schedules remind-at when far away and ample time', () async {
    await enrich(
      _input(
        now: DateTime(2026, 6, 14, 12, 0),
        firstItem: DateTime(2026, 6, 14, 19, 0),
        travel: const Duration(minutes: 45),
        meters: 30000,
      ),
      scheduler,
    );
    expect(scheduler.scheduled.length, 1);
    expect(scheduler.scheduled.single.id, 42);
    expect(scheduler.scheduled.single.when, DateTime(2026, 6, 14, 18, 0));
    expect(scheduler.scheduled.single.body, contains('Leave by 6:15pm for Load In'));
  });

  test('suppresses + cancels when within arrival radius', () async {
    await enrich(
      _input(
        now: DateTime(2026, 6, 14, 18, 30),
        firstItem: DateTime(2026, 6, 14, 19, 0),
        travel: const Duration(minutes: 3),
        meters: 100,
      ),
      scheduler,
    );
    expect(scheduler.scheduled, isEmpty);
    expect(scheduler.cancelled, contains(42));
  });

  test('skips when remind time already past', () async {
    await enrich(
      _input(
        now: DateTime(2026, 6, 14, 18, 10),
        firstItem: DateTime(2026, 6, 14, 19, 0),
        travel: const Duration(minutes: 45),
        meters: 30000,
      ),
      scheduler,
    );
    expect(scheduler.scheduled, isEmpty);
    expect(scheduler.cancelled, isEmpty);
  });
}
