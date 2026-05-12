import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/bookings_repository.dart';
import 'package:tts_bandmate/features/bookings/data/models/event_draft.dart';
import 'package:tts_bandmate/features/bookings/services/booking_save_orchestrator.dart';
import 'package:tts_bandmate/features/events/data/events_repository.dart';

/// Records every HTTP call and returns canned responses keyed by
/// "METHOD path" → response factory.
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.script);
  final Map<String, ResponseBody Function()> script;
  final List<RequestOptions> calls = [];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    calls.add(options);
    final key = '${options.method} ${options.path}';
    final builder = script[key];
    if (builder == null) {
      return _json(500, {'message': 'Unscripted: $key'});
    }
    return builder();
  }
}

ResponseBody _json(int status, Object body) {
  final encoded = utf8.encode(jsonEncode(body));
  return ResponseBody.fromBytes(encoded, status, headers: {
    'content-type': ['application/json'],
  });
}

Dio _dio(_ScriptedAdapter adapter) => Dio(
      BaseOptions(baseUrl: 'http://test.local'),
    )..httpClientAdapter = adapter;

BookingSaveOrchestrator _orchestrator(_ScriptedAdapter adapter) {
  final dio = _dio(adapter);
  return BookingSaveOrchestrator(
    bookingsRepository: BookingsRepository(dio),
    eventsRepository: EventsRepository(dio),
  );
}

Map<String, dynamic> _bookingFixture() => {
      'id': 42,
      'name': 'Test',
      'start_date': '2026-06-13',
      'end_date': '2026-06-13',
      'event_count': 1,
      'is_multi_event': false,
      'is_paid': false,
      'contacts': [],
      'events': [],
      'payments': [],
    };

Map<String, dynamic> _eventFixture(int id) => {
      'id': id,
      'key': 'evt_$id',
      'title': 'E',
      'date': '2026-06-13',
      'event_source': 'booking',
      'can_write': false,
      'members': [],
      'timeline': [],
      'lodging': [],
      'contacts': [],
      'attachments': [],
    };

void main() {
  group('BookingSaveOrchestrator.save', () {
    test('empty snapshot — no API calls, allSucceeded', () async {
      final adapter = _ScriptedAdapter({});
      final orch = _orchestrator(adapter);
      final result = await orch.save(
        bandId: 7,
        bookingId: 42,
        snapshot: const BookingFormSnapshot(),
      );
      expect(adapter.calls, isEmpty);
      expect(result.allSucceeded, isTrue);
    });

    test('booking patch only succeeds', () async {
      final adapter = _ScriptedAdapter({
        'PATCH /api/mobile/bands/7/bookings/42': () =>
            _json(200, {'booking': _bookingFixture()}),
      });
      final orch = _orchestrator(adapter);
      final result = await orch.save(
        bandId: 7,
        bookingId: 42,
        snapshot: const BookingFormSnapshot(
          bookingPatch: BookingFieldDiff(name: 'Renamed'),
        ),
      );
      expect(adapter.calls, hasLength(1));
      expect(result.allSucceeded, isTrue);
    });

    test('booking patch fails — event sub-ops skipped', () async {
      final adapter = _ScriptedAdapter({
        'PATCH /api/mobile/bands/7/bookings/42': () =>
            _json(422, {'message': 'Validation failed'}),
      });
      final orch = _orchestrator(adapter);
      final result = await orch.save(
        bandId: 7,
        bookingId: 42,
        snapshot: const BookingFormSnapshot(
          bookingPatch: BookingFieldDiff(name: 'Bad'),
          eventDeletes: {99},
        ),
      );
      // Only the PATCH was attempted; the DELETE did not fire.
      expect(adapter.calls, hasLength(1));
      expect(result.bookingPatch, isA<OperationFailure>());
      expect(result.eventDeletes[99], isA<OperationPending>());
    });

    test('all event PUTs succeed (keyed by event UUID)', () async {
      // EventsRepository.updateEvent uses PATCH /api/mobile/events/{key}
      final adapter = _ScriptedAdapter({
        'PATCH /api/mobile/events/evt_1': () =>
            _json(200, {'event': _eventFixture(1)}),
        'PATCH /api/mobile/events/evt_2': () =>
            _json(200, {'event': _eventFixture(2)}),
      });
      final orch = _orchestrator(adapter);
      final result = await orch.save(
        bandId: 7,
        bookingId: 42,
        snapshot: const BookingFormSnapshot(
          eventUpdates: {
            'evt_1': EventDraft(title: 'A', date: '2026-06-13'),
            'evt_2': EventDraft(title: 'B', date: '2026-06-14'),
          },
        ),
      );
      expect(adapter.calls, hasLength(2));
      expect(result.allSucceeded, isTrue);
    });

    test('all event POSTs succeed', () async {
      final adapter = _ScriptedAdapter({
        'POST /api/mobile/bands/7/bookings/42/events': () =>
            _json(200, {'event': _eventFixture(99)}),
      });
      final orch = _orchestrator(adapter);
      final result = await orch.save(
        bandId: 7,
        bookingId: 42,
        snapshot: const BookingFormSnapshot(
          eventCreates: {
            'new-1': EventDraft(title: 'New', date: '2026-06-15'),
          },
        ),
      );
      expect(result.allSucceeded, isTrue);
    });

    test('all event DELETEs succeed', () async {
      final adapter = _ScriptedAdapter({
        'DELETE /api/mobile/bands/7/bookings/42/events/9': () =>
            _json(200, {'success': true}),
      });
      final orch = _orchestrator(adapter);
      final result = await orch.save(
        bandId: 7,
        bookingId: 42,
        snapshot: const BookingFormSnapshot(eventDeletes: {9}),
      );
      expect(result.allSucceeded, isTrue);
    });

    test('event DELETE 422 — captured as OperationFailure with message',
        () async {
      final adapter = _ScriptedAdapter({
        'DELETE /api/mobile/bands/7/bookings/42/events/9': () => _json(
            422, {'message': 'Cannot delete the last event of a booking.'}),
      });
      final orch = _orchestrator(adapter);
      final result = await orch.save(
        bandId: 7,
        bookingId: 42,
        snapshot: const BookingFormSnapshot(eventDeletes: {9}),
      );
      final status = result.eventDeletes[9];
      expect(status, isA<OperationFailure>());
      expect(
          (status as OperationFailure).message, contains('Cannot delete'));
    });

    test('mixed success/failure — partiallySucceeded', () async {
      final adapter = _ScriptedAdapter({
        'PATCH /api/mobile/bands/7/bookings/42': () =>
            _json(200, {'booking': _bookingFixture()}),
        'PATCH /api/mobile/events/evt_1': () =>
            _json(200, {'event': _eventFixture(1)}),
        'POST /api/mobile/bands/7/bookings/42/events': () =>
            _json(500, {'message': 'Server error'}),
        'DELETE /api/mobile/bands/7/bookings/42/events/9': () =>
            _json(200, {'success': true}),
      });
      final orch = _orchestrator(adapter);
      final result = await orch.save(
        bandId: 7,
        bookingId: 42,
        snapshot: const BookingFormSnapshot(
          bookingPatch: BookingFieldDiff(name: 'X'),
          eventUpdates: {
            'evt_1': EventDraft(title: 'A', date: '2026-06-13'),
          },
          eventCreates: {
            'new-1': EventDraft(title: 'N', date: '2026-06-15'),
          },
          eventDeletes: {9},
        ),
      );
      expect(result.partiallySucceeded, isTrue);
      expect(result.failedCount, 1);
      expect(result.failureKeys.first.key, 'NEW-new-1');
    });

    test('network-out — every call 500 — allFailed', () async {
      final adapter = _ScriptedAdapter({}); // every request → 500
      final orch = _orchestrator(adapter);
      final result = await orch.save(
        bandId: 7,
        bookingId: 42,
        snapshot: const BookingFormSnapshot(
          bookingPatch: BookingFieldDiff(name: 'X'),
        ),
      );
      expect(result.allFailed, isTrue);
    });

    test('retry semantics — second save with reduced snapshot fires one request',
        () async {
      var postShouldFail = true;
      final adapter = _ScriptedAdapter({
        'PATCH /api/mobile/bands/7/bookings/42': () =>
            _json(200, {'booking': _bookingFixture()}),
        'POST /api/mobile/bands/7/bookings/42/events': () => postShouldFail
            ? _json(500, {'message': 'oops'})
            : _json(200, {'event': _eventFixture(99)}),
      });
      final orch = _orchestrator(adapter);

      final first = await orch.save(
        bandId: 7,
        bookingId: 42,
        snapshot: const BookingFormSnapshot(
          bookingPatch: BookingFieldDiff(name: 'X'),
          eventCreates: {
            'new-1': EventDraft(title: 'N', date: '2026-06-15'),
          },
        ),
      );
      expect(first.partiallySucceeded, isTrue);

      postShouldFail = false;
      adapter.calls.clear();
      final second = await orch.save(
        bandId: 7,
        bookingId: 42,
        snapshot: const BookingFormSnapshot(
          eventCreates: {
            'new-1': EventDraft(title: 'N', date: '2026-06-15'),
          },
        ),
      );
      expect(adapter.calls, hasLength(1));
      expect(second.allSucceeded, isTrue);
    });
  });
}
