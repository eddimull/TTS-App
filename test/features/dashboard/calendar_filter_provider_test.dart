import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/dashboard/providers/calendar_filter_provider.dart';
import 'package:tts_bandmate/features/events/data/models/event_summary.dart';

EventSummary _event({
  required int bandId,
  required String source,
  String key = 'evt',
}) =>
    EventSummary(
      key: key,
      title: 't',
      date: '2026-05-02',
      eventSource: source,
      band: BandSummary(id: bandId, name: 'B$bandId', isOwner: false),
    );

void main() {
  group('CalendarFilterState', () {
    test('default state is not active and visible to all events', () {
      const state = CalendarFilterState();
      expect(state.isActive, false);
      expect(state.activeCount, 0);
      expect(state.isEventVisible(_event(bandId: 1, source: 'booking')), true);
    });

    test('hidden band id hides matching event', () {
      const state = CalendarFilterState(hiddenBandIds: {7});
      expect(state.isEventVisible(_event(bandId: 7, source: 'booking')), false);
      expect(state.isEventVisible(_event(bandId: 8, source: 'booking')), true);
    });

    test('hidden event type hides matching event regardless of band', () {
      const state =
          CalendarFilterState(hiddenEventTypes: {'rehearsal'});
      expect(state.isEventVisible(_event(bandId: 1, source: 'rehearsal')),
          false);
      expect(state.isEventVisible(_event(bandId: 1, source: 'booking')), true);
    });

    test('event without band is unaffected by hiddenBandIds', () {
      const eventWithoutBand = EventSummary(
        key: 'k',
        title: 't',
        date: '2026-05-02',
        eventSource: 'booking',
      );
      const state = CalendarFilterState(hiddenBandIds: {7});
      expect(state.isEventVisible(eventWithoutBand), true);
    });

    test('activeCount sums hidden bands + hidden types', () {
      const state = CalendarFilterState(
        hiddenBandIds: {1, 2},
        hiddenEventTypes: {'rehearsal'},
      );
      expect(state.activeCount, 3);
      expect(state.isActive, true);
    });
  });

  group('CalendarFilterNotifier', () {
    test('toggleBand adds and removes a band id', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(calendarFilterProvider.notifier);

      notifier.toggleBand(5);
      expect(container.read(calendarFilterProvider).hiddenBandIds, {5});

      notifier.toggleBand(5);
      expect(container.read(calendarFilterProvider).hiddenBandIds, isEmpty);
    });

    test('toggleEventType adds and removes a source', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(calendarFilterProvider.notifier);

      notifier.toggleEventType('rehearsal');
      expect(container.read(calendarFilterProvider).hiddenEventTypes,
          {'rehearsal'});

      notifier.toggleEventType('rehearsal');
      expect(container.read(calendarFilterProvider).hiddenEventTypes,
          isEmpty);
    });

    test('clear resets state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(calendarFilterProvider.notifier);
      notifier.toggleBand(1);
      notifier.toggleEventType('booking');
      expect(container.read(calendarFilterProvider).isActive, true);

      notifier.clear();
      expect(container.read(calendarFilterProvider).isActive, false);
    });
  });
}
