import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/events/data/events_repository.dart';
import 'package:tts_bandmate/features/events/data/models/event_detail.dart';
import 'package:tts_bandmate/features/events/data/models/event_summary.dart';
import 'package:tts_bandmate/features/events/providers/events_provider.dart';

// ── Fake repository ───────────────────────────────────────────────────────────

class FakeEventsRepository implements EventsRepository {
  FakeEventsRepository({
    List<EventSummary>? events,
    EventDetail? detail,
  })  : _events = events ?? [],
        _detail = detail;

  final List<EventSummary> _events;
  final EventDetail? _detail;
  int listCallCount = 0;
  int detailCallCount = 0;

  @override
  Future<List<EventSummary>> getBandEvents(
    int bandId, {
    String? from,
    String? to,
  }) async {
    listCallCount++;
    return _events;
  }

  @override
  Future<EventDetail> getEventDetail(String key) async {
    detailCallCount++;
    if (_detail == null) throw Exception('Not found');
    return _detail;
  }

  @override
  Future<void> updateEvent(String key, Map<String, dynamic> data) async {}

  @override
  Future<EventAttachment> uploadAttachment(String key, dynamic file) async =>
      throw UnimplementedError();

  @override
  Future<void> deleteAttachment(String key, int attachmentId) async {}
}

// ── Fixtures ──────────────────────────────────────────────────────────────────

EventSummary _makeEvent(String key, {String source = 'booking'}) =>
    EventSummary.fromJson({
      'id': key.hashCode.abs(),
      'key': key,
      'title': 'Event $key',
      'date': '2026-04-15',
      'event_source': source,
    });

EventDetail _makeDetail(String key) => EventDetail.fromJson({
      'id': 1,
      'key': key,
      'title': 'Event $key',
      'date': '2026-04-15',
      'can_write': true,
      'members': [],
    });

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('bandEventsProvider', () {
    ProviderContainer makeContainer(FakeEventsRepository repo) {
      return ProviderContainer(
        overrides: [eventsRepositoryProvider.overrideWithValue(repo)],
      );
    }

    test('test_returns_events_for_band', () async {
      final repo = FakeEventsRepository(
        events: [_makeEvent('e1'), _makeEvent('e2')],
      );
      final container = makeContainer(repo);
      addTearDown(container.dispose);

      const params = BandEventsParams(bandId: 10);
      final events = await container.read(bandEventsProvider(params).future);

      expect(events, hasLength(2));
      expect(events.first.key, 'e1');
    });

    test('test_returns_empty_list_when_no_events', () async {
      final repo = FakeEventsRepository(events: []);
      final container = makeContainer(repo);
      addTearDown(container.dispose);

      final events = await container.read(
        bandEventsProvider(const BandEventsParams(bandId: 5)).future,
      );

      expect(events, isEmpty);
    });

    test('test_refresh_calls_repository_again', () async {
      final repo = FakeEventsRepository(events: [_makeEvent('e1')]);
      final container = makeContainer(repo);
      addTearDown(container.dispose);

      const params = BandEventsParams(bandId: 10);
      await container.read(bandEventsProvider(params).future);
      expect(repo.listCallCount, 1);

      await container.read(bandEventsProvider(params).notifier).refresh();
      expect(repo.listCallCount, 2);
    });

    test('test_different_params_are_independent_providers', () async {
      final repo = FakeEventsRepository(events: [_makeEvent('e1')]);
      final container = makeContainer(repo);
      addTearDown(container.dispose);

      // Reading two different bandIds should make two separate calls
      await container.read(bandEventsProvider(const BandEventsParams(bandId: 1)).future);
      await container.read(bandEventsProvider(const BandEventsParams(bandId: 2)).future);

      expect(repo.listCallCount, 2);
    });
  });

  group('eventDetailProvider', () {
    ProviderContainer makeContainer(FakeEventsRepository repo) {
      return ProviderContainer(
        overrides: [eventsRepositoryProvider.overrideWithValue(repo)],
      );
    }

    test('test_returns_event_detail_for_key', () async {
      final detail = _makeDetail('evt-key');
      final repo = FakeEventsRepository(detail: detail);
      final container = makeContainer(repo);
      addTearDown(container.dispose);

      final result = await container.read(eventDetailProvider('evt-key').future);

      expect(result.key, 'evt-key');
      expect(result.canWrite, isTrue);
    });

    test('test_propagates_error_when_not_found', () async {
      final repo = FakeEventsRepository(); // no detail set → throws
      final container = makeContainer(repo);
      addTearDown(container.dispose);

      final result = await container
          .read(eventDetailProvider('missing').future)
          .then((_) => 'ok', onError: (_) => 'error');

      expect(result, 'error');
    });
  });
}
