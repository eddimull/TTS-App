import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_detail.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_summary.dart';
import 'package:tts_bandmate/features/bookings/data/models/event_draft.dart';
import 'package:tts_bandmate/features/events/data/models/event_summary.dart';

Map<String, dynamic> _singleEventBookingJson({Map<String, dynamic>? overrides}) {
  return {
    'id': 1,
    'name': 'Anniversary Gig',
    'start_date': '2026-06-13',
    'end_date': '2026-06-13',
    'event_count': 1,
    'is_multi_event': false,
    'venue_summary': 'Symphony Hall',
    'status': 'pending',
    'price': '1200.00',
    'event_type_id': 2,
    'notes': null,
    'amount_paid': '0.00',
    'amount_due': '1200.00',
    'is_paid': false,
    'contacts': [],
    'events': [
      {
        'id': 100,
        'key': 'evt_100',
        'title': 'Anniversary Performance',
        'date': '2026-06-13',
        'start_time': '19:00',
        'end_time': '22:00',
        'venue_name': 'Symphony Hall',
        'price': null,
        'event_source': 'booking',
      }
    ],
    ...?overrides,
  };
}

Map<String, dynamic> _multiEventBookingJson() {
  return {
    'id': 2,
    'name': 'Three Show Run',
    'start_date': '2026-06-12',
    'end_date': '2026-06-14',
    'event_count': 3,
    'is_multi_event': true,
    'venue_summary': 'Symphony Hall',
    'status': 'pending',
    'price': '5000.00',
    'event_type_id': 2,
    'notes': null,
    'amount_paid': '0.00',
    'amount_due': '5000.00',
    'is_paid': false,
    'contacts': [],
    'events': [
      {
        'id': 200,
        'key': 'evt_200',
        'title': 'Rehearsal',
        'date': '2026-06-12',
        'start_time': '19:00',
        'end_time': '21:00',
        'venue_name': 'Symphony Hall',
        'price': null,
        'event_source': 'booking',
      },
      {
        'id': 201,
        'key': 'evt_201',
        'title': 'Saturday',
        'date': '2026-06-13',
        'start_time': '19:00',
        'end_time': '21:00',
        'venue_name': 'Symphony Hall',
        'price': null,
        'event_source': 'booking',
      },
      {
        'id': 202,
        'key': 'evt_202',
        'title': 'Sunday',
        'date': '2026-06-14',
        'start_time': '19:00',
        'end_time': '21:00',
        'venue_name': 'Symphony Hall',
        'price': null,
        'event_source': 'booking',
      },
    ],
  };
}

void main() {
  group('BookingSummary.fromJson', () {
    test('parses single-event payload', () {
      final s = BookingSummary.fromJson(_singleEventBookingJson());
      expect(s.id, 1);
      expect(s.name, 'Anniversary Gig');
      expect(s.startDate, '2026-06-13');
      expect(s.endDate, '2026-06-13');
      expect(s.eventCount, 1);
      expect(s.isMultiEvent, false);
      expect(s.venueSummary, 'Symphony Hall');
      expect(s.events, hasLength(1));
      expect(s.events.first, isA<EventSummary>());
      expect(s.events.first.title, 'Anniversary Performance');
      expect(s.events.first.startTime, '19:00');
    });

    test('parses multi-event payload', () {
      final s = BookingSummary.fromJson(_multiEventBookingJson());
      expect(s.eventCount, 3);
      expect(s.isMultiEvent, true);
      expect(s.startDate, '2026-06-12');
      expect(s.endDate, '2026-06-14');
      expect(s.events, hasLength(3));
    });

    test('displayDateRange — single event', () {
      final s = BookingSummary.fromJson(_singleEventBookingJson());
      expect(s.displayDateRange, 'Jun 13');
    });

    test('displayDateRange — same-month multi-event', () {
      final s = BookingSummary.fromJson(_multiEventBookingJson());
      expect(s.displayDateRange, 'Jun 12–14');
    });

    test('displayDateRange — cross-month multi-event', () {
      final json = _multiEventBookingJson()
        ..['start_date'] = '2026-06-30'
        ..['end_date'] = '2026-07-02';
      final s = BookingSummary.fromJson(json);
      expect(s.displayDateRange, 'Jun 30 – Jul 2');
    });

    test('tolerates missing events key (treats as empty)', () {
      final json = _singleEventBookingJson();
      json.remove('events');
      final s = BookingSummary.fromJson(json);
      expect(s.events, isEmpty);
    });
  });

  group('BookingDetail.fromJson', () {
    test('parses multi-event payload with nested events', () {
      final detailJson = _multiEventBookingJson()
        ..['payments'] = []
        ..['contract'] = null;
      final d = BookingDetail.fromJson(detailJson);
      expect(d.eventCount, 3);
      expect(d.events, hasLength(3));
      expect(d.events.first, isA<EventSummary>());
      expect(d.events.first.startTime, '19:00');
    });
  });

  group('EventDraft.toJson', () {
    test('omits null optional fields', () {
      const d = EventDraft(
        title: 'Rehearsal',
        date: '2026-06-12',
      );
      final json = d.toJson();
      expect(json, equals({
        'title': 'Rehearsal',
        'date': '2026-06-12',
      }));
    });

    test('includes optional fields when set', () {
      const d = EventDraft(
        title: 'Show',
        date: '2026-06-13',
        startTime: '19:00',
        endTime: '22:00',
        venueName: 'Symphony Hall',
        venueAddress: '123 Main',
        price: '1500.00',
      );
      final json = d.toJson();
      expect(json['start_time'], '19:00');
      expect(json['end_time'], '22:00');
      expect(json['venue_name'], 'Symphony Hall');
      expect(json['venue_address'], '123 Main');
      expect(json['price'], '1500.00');
    });
  });
}
