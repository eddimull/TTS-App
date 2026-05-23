import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/events/data/models/event_summary.dart';

void main() {
  group('EventSummary.fromJson', () {
    test('test_parses_full_booking_event', () {
      final json = {
        'id': 42,
        'key': 'abc123',
        'title': 'Corporate Gig',
        'date': '2026-04-15',
        'time': '19:00',
        'event_type': 'Corporate',
        'event_source': 'booking',
        'venue_name': 'The Grand Hotel',
        'venue_address': '123 Main St',
        'status': 'confirmed',
        'live_session_id': 7,
      };

      final event = EventSummary.fromJson(json);

      expect(event.id, 42);
      expect(event.key, 'abc123');
      expect(event.title, 'Corporate Gig');
      expect(event.date, '2026-04-15');
      expect(event.time, '19:00');
      expect(event.eventType, 'Corporate');
      expect(event.eventSource, 'booking');
      expect(event.venueName, 'The Grand Hotel');
      expect(event.venueAddress, '123 Main St');
      expect(event.status, 'confirmed');
      expect(event.liveSessionId, 7);
    });

    test('test_parses_rehearsal_event_with_null_fields', () {
      final json = {
        'id': 5,
        'key': 'reh001',
        'title': 'Weekly Rehearsal',
        'date': '2026-04-10',
        'time': null,
        'event_type': 'Rehearsal',
        'event_source': 'rehearsal',
        'venue_name': null,
        'venue_address': null,
        'status': null,
        'live_session_id': null,
      };

      final event = EventSummary.fromJson(json);

      expect(event.time, isNull);
      expect(event.venueName, isNull);
      expect(event.liveSessionId, isNull);
      expect(event.isRehearsal, isTrue);
    });

    test('test_is_rehearsal_false_for_booking', () {
      final event = EventSummary.fromJson({
        'id': 1, 'key': 'k', 'title': 'T', 'date': '2026-01-01',
        'event_source': 'booking',
      });
      expect(event.isRehearsal, isFalse);
    });

    test('test_parsed_date_returns_correct_datetime', () {
      final event = EventSummary.fromJson({
        'id': 1, 'key': 'k', 'title': 'T', 'date': '2026-04-15',
        'event_source': 'booking',
      });
      final date = event.parsedDate;
      expect(date.year, 2026);
      expect(date.month, 4);
      expect(date.day, 15);
    });

    test('test_parsed_date_falls_back_on_invalid_string', () {
      final event = EventSummary.fromJson({
        'id': 1, 'key': 'k', 'title': 'T', 'date': 'not-a-date',
        'event_source': 'booking',
      });
      // Should not throw — returns DateTime.now() fallback
      expect(() => event.parsedDate, returnsNormally);
    });

    test('test_missing_event_source_defaults_to_band_event', () {
      final event = EventSummary.fromJson({
        'id': 1, 'key': 'k', 'title': 'T', 'date': '2026-01-01',
      });
      expect(event.eventSource, 'band_event');
    });

    test('normalizes rehearsal_schedule to rehearsal', () {
      final event = EventSummary.fromJson({
        'id': 10, 'key': 'rs001', 'title': 'Virtual Rehearsal',
        'date': '2026-05-10', 'event_source': 'rehearsal_schedule',
      });
      expect(event.eventSource, 'rehearsal');
      expect(event.isRehearsal, isTrue);
    });

    test('preserves rehearsal as rehearsal', () {
      final event = EventSummary.fromJson({
        'id': 11, 'key': 'rh001', 'title': 'Weekly Rehearsal',
        'date': '2026-05-11', 'event_source': 'rehearsal',
      });
      expect(event.eventSource, 'rehearsal');
      expect(event.isRehearsal, isTrue);
    });

    test('test_equality_based_on_key', () {
      final a = EventSummary.fromJson({
        'id': 1, 'key': 'same-key', 'title': 'A', 'date': '2026-01-01',
        'event_source': 'booking',
      });
      final b = EventSummary.fromJson({
        'id': 99, 'key': 'same-key', 'title': 'B', 'date': '2026-06-01',
        'event_source': 'rehearsal',
      });
      expect(a, equals(b));
    });
  });

  group('EventSummary.fromJson — band field', () {
    test('parses nested band when present', () {
      final event = EventSummary.fromJson({
        'key': 'evt-1',
        'title': 'A Gig',
        'date': '2026-06-01',
        'event_source': 'booking',
        'band': {
          'id': 7,
          'name': 'Test Band',
          'is_owner': true,
          'is_personal': false,
          'logo_url': null,
        },
      });
      expect(event.band, isNotNull);
      expect(event.band!.id, equals(7));
      expect(event.band!.isPersonal, isFalse);
    });

    test('parses personal band', () {
      final event = EventSummary.fromJson({
        'key': 'evt-3',
        'title': 'Church',
        'date': '2026-06-03',
        'event_source': 'booking',
        'band': {
          'id': 99,
          'name': "Eddie's Band",
          'is_owner': true,
          'is_personal': true,
          'logo_url': null,
        },
      });
      expect(event.band, isNotNull);
      expect(event.band!.isPersonal, isTrue);
    });

    test('tolerates missing band field', () {
      final event = EventSummary.fromJson({
        'key': 'evt-2',
        'title': 'Old',
        'date': '2026-06-02',
        'event_source': 'band_event',
      });
      expect(event.band, isNull);
    });

    test('tolerates explicit null band', () {
      final event = EventSummary.fromJson({
        'key': 'evt-4',
        'title': 'Defensive',
        'date': '2026-06-04',
        'event_source': 'booking',
        'band': null,
      });
      expect(event.band, isNull);
    });
  });

  group('EventSummary.gigIconPath', () {
    EventSummary make(String? type, {String source = 'booking'}) =>
        EventSummary.fromJson({
          'key': 'k',
          'title': 'T',
          'date': '2026-01-01',
          'event_source': source,
          if (type != null) 'event_type': type,
        });

    test('rehearsal returns null', () {
      expect(make('Wedding', source: 'rehearsal').gigIconPath, isNull);
    });

    test('maps every web-app event type name to its icon', () {
      // Source of truth: resources/js/Components/Event/Card/CardIcon.vue
      // in the eddimull/TTS repo.
      const mapping = {
        'Wedding': 'assets/images/gigIcons/wedding.png',
        'Bar Gig': 'assets/images/gigIcons/bar.png',
        'Casino': 'assets/images/gigIcons/casino.png',
        'Special Event': 'assets/images/gigIcons/special.png',
        'Charity': 'assets/images/gigIcons/charity.png',
        'Festival': 'assets/images/gigIcons/festival.png',
        'Private Party': 'assets/images/gigIcons/private.png',
        'Mardi Gras Ball': 'assets/images/gigIcons/mardiGras.png',
      };
      for (final entry in mapping.entries) {
        expect(make(entry.key).gigIconPath, entry.value,
            reason: 'event_type "${entry.key}" should map to ${entry.value}');
      }
    });

    test('unknown type falls back to other.png', () {
      expect(make('Corporate').gigIconPath, 'assets/images/gigIcons/other.png');
      expect(make(null).gigIconPath, 'assets/images/gigIcons/other.png');
    });

    test('normalization ignores case and spacing', () {
      expect(make('bar gig').gigIconPath, 'assets/images/gigIcons/bar.png');
      expect(make('BAR  GIG').gigIconPath, 'assets/images/gigIcons/bar.png');
      expect(make('MardiGrasBall').gigIconPath,
          'assets/images/gigIcons/mardiGras.png');
    });
  });
}
