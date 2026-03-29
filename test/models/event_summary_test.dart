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
}
