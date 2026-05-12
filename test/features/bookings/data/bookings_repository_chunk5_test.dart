import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/bookings_repository.dart';
import 'package:tts_bandmate/features/bookings/data/models/event_draft.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);
  final Future<ResponseBody> Function(RequestOptions) handler;
  RequestOptions? lastRequest;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
      Future<void>? cancel) async {
    lastRequest = options;
    return handler(options);
  }
}

ResponseBody _json(int status, Object body) {
  final encoded = utf8.encode(jsonEncode(body));
  return ResponseBody.fromBytes(encoded, status, headers: {
    'content-type': ['application/json'],
  });
}

Map<String, dynamic> _bookingFixture(int id, {bool multi = false}) => {
      'id': id,
      'name': multi ? 'Three Show Run' : 'Solo',
      'start_date': '2026-06-13',
      'end_date': multi ? '2026-06-14' : '2026-06-13',
      'event_count': multi ? 3 : 1,
      'is_multi_event': multi,
      'venue_summary': 'Symphony Hall',
      'price': '1200.00',
      'is_paid': false,
      'contacts': [],
      'events': [],
      'payments': [],
    };

Map<String, dynamic> _eventFixture(int id) => {
      'id': id,
      'key': 'evt_$id',
      'title': 'New Event',
      'date': '2026-06-14',
      'start_time': '19:00',
      'end_time': '22:00',
      'venue_name': 'Symphony Hall',
      'event_source': 'booking',
      'can_write': false,
      'members': [],
      'timeline': [],
      'lodging': [],
      'contacts': [],
      'attachments': [],
    };

Dio _dio(_StubAdapter adapter) =>
    Dio(BaseOptions(baseUrl: 'http://test.local'))..httpClientAdapter = adapter;

void main() {
  group('BookingsRepository.createBooking', () {
    test('POSTs to /api/mobile/bands/{band}/bookings with events array', () async {
      final adapter = _StubAdapter((req) async {
        return _json(200, {'booking': _bookingFixture(42)});
      });
      final repo = BookingsRepository(_dio(adapter));

      final result = await repo.createBooking(
        7,
        name: 'Solo',
        eventTypeId: 2,
        price: '1200.00',
        status: 'pending',
        contractOption: 'default',
        events: [
          const EventDraft(
            title: 'Performance',
            date: '2026-06-13',
            startTime: '19:00',
            endTime: '22:00',
            venueName: 'Symphony Hall',
          ),
        ],
      );

      expect(adapter.lastRequest!.method, 'POST');
      expect(adapter.lastRequest!.path, '/api/mobile/bands/7/bookings');
      final body = adapter.lastRequest!.data as Map<String, dynamic>;
      expect(body['name'], 'Solo');
      expect(body['event_type_id'], 2);
      expect(body['events'], hasLength(1));
      expect(body['events'][0]['title'], 'Performance');
      expect(body['events'][0]['start_time'], '19:00');
      expect(result.id, 42);
    });
  });

  group('BookingsRepository.updateBooking', () {
    test('PATCHes with booking-level fields only', () async {
      final adapter = _StubAdapter((req) async {
        return _json(200, {'booking': _bookingFixture(42)});
      });
      final repo = BookingsRepository(_dio(adapter));

      await repo.updateBooking(7, 42, name: 'Renamed', price: '1500.00');

      expect(adapter.lastRequest!.method, 'PATCH');
      expect(adapter.lastRequest!.path, '/api/mobile/bands/7/bookings/42');
      final body = adapter.lastRequest!.data as Map<String, dynamic>;
      expect(body, equals({'name': 'Renamed', 'price': '1500.00'}));
      // None of the prohibited keys leak through.
      expect(body.containsKey('date'), isFalse);
      expect(body.containsKey('venue_name'), isFalse);
      expect(body.containsKey('start_time'), isFalse);
    });
  });

  group('BookingsRepository.addEventToBooking', () {
    test('POSTs to the booking-events subresource', () async {
      final adapter = _StubAdapter((req) async {
        return _json(200, {'event': _eventFixture(99)});
      });
      final repo = BookingsRepository(_dio(adapter));

      const draft = EventDraft(
        title: 'New Event',
        date: '2026-06-14',
        startTime: '19:00',
        endTime: '22:00',
        venueName: 'Symphony Hall',
      );
      final result = await repo.addEventToBooking(7, 42, draft);

      expect(adapter.lastRequest!.method, 'POST');
      expect(adapter.lastRequest!.path, '/api/mobile/bands/7/bookings/42/events');
      final body = adapter.lastRequest!.data as Map<String, dynamic>;
      expect(body['title'], 'New Event');
      expect(body['date'], '2026-06-14');
      expect(body['start_time'], '19:00');
      expect(result.id, 99);
    });
  });

  group('BookingsRepository.removeEventFromBooking', () {
    test('DELETEs the booking-event subresource path', () async {
      final adapter = _StubAdapter((req) async {
        return _json(200, {'success': true});
      });
      final repo = BookingsRepository(_dio(adapter));

      await repo.removeEventFromBooking(7, 42, 99);

      expect(adapter.lastRequest!.method, 'DELETE');
      expect(adapter.lastRequest!.path, '/api/mobile/bands/7/bookings/42/events/99');
    });

    test('propagates a 422 server error as DioException', () async {
      final adapter = _StubAdapter((req) async {
        return _json(422, {
          'message': 'Cannot delete the last event of a booking.',
          'errors': {'event': ['Cannot delete the last event of a booking.']},
        });
      });
      final repo = BookingsRepository(_dio(adapter));

      expect(
        () => repo.removeEventFromBooking(7, 42, 99),
        throwsA(isA<DioException>()),
      );
    });
  });
}
