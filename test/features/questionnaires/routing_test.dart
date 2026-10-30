import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/bookings_repository.dart';
import 'package:tts_bandmate/features/events/data/models/event_detail.dart';
import 'package:tts_bandmate/features/questionnaires/data/models/routing_preview.dart';
import 'package:tts_bandmate/features/questionnaires/providers/questionnaires_provider.dart';
import 'package:tts_bandmate/features/questionnaires/providers/routing_provider.dart';
import 'package:tts_bandmate/shared/cache/cache_invalidator.dart';
import 'fake_questionnaires_repository.dart';

const _key = (bandId: 1, instanceId: 7);

class _RecordingAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? stream, Future<void>? cancel) async {
    requests.add(options);
    return ResponseBody.fromBytes(utf8.encode(jsonEncode({'contacts': []})), 200,
        headers: {
          'content-type': ['application/json'],
        });
  }
}

Map<String, dynamic> _previewJson() => {
      'groups': [
        {
          'key': 'timeline',
          'label': 'Timeline',
          'items': [
            {
              'response_id': 1,
              'field_label': 'First Dance',
              'value_display': 'Forever and Ever, Amen by Randy Travis',
              'target': 'wedding.dance.first',
              'target_label': 'First dance',
              'status': 'pending',
              'default_checked': true,
            },
            {
              'response_id': 2,
              'field_label': 'Money dance',
              'value_display': 'tbd',
              'target': 'wedding.dance.money',
              'target_label': 'Money dance',
              'status': 'pending',
              'default_checked': false,
            },
          ],
        },
        {
          'key': 'performance',
          'label': 'Performance notes',
          'items': [
            {
              'response_id': 3,
              'field_label': 'Anything else?',
              'value_display': 'Only upbeat songs',
              'target': 'performance.notes',
              'target_label': 'Performance notes',
            },
          ],
        },
      ],
      'conflicts': [
        {
          'kind': 'song_both_lists',
          'song_id': 12,
          'title': 'We Are Family',
          'resolution': null,
        },
        {
          'kind': 'venue_mismatch',
          'booking_value': 'Il Mercato',
          'form_value': 'II Mercato',
          'resolution': null,
        },
        {'kind': 'something_new'},
      ],
      'song_requests': {
        'must_play': 32,
        'do_not_play': 34,
        'write_ins': ['Here for a Good Time'],
      },
      'contacts': [
        {'name': 'Grace Terreson', 'on_booking': true},
      ],
      'unrouted': [
        {
          'response_id': 9,
          'field_label': 'Names and order of toasts',
          'value_display': 'Paul Looney',
          'compatible_targets': ['wedding.toasts', 'performance.notes'],
        },
      ],
    };

/// Records event invalidations instead of touching the real caches.
class _FakeInvalidator extends Fake implements CacheInvalidator {
  final appliedBands = <int>[];
  @override
  void onQuestionnaireAppliedToEvents({required int bandId}) =>
      appliedBands.add(bandId);
}

void main() {
  late _FakeInvalidator invalidator;
  setUp(() => invalidator = _FakeInvalidator());

  ProviderContainer makeContainer(FakeQuestionnairesRepository repo) =>
      ProviderContainer(
        overrides: [
          questionnairesRepositoryProvider.overrideWithValue(repo),
          cacheInvalidatorProvider.overrideWithValue(invalidator),
        ],
      );

  Future<ProviderContainer> loaded(FakeQuestionnairesRepository repo) async {
    final c = makeContainer(repo);
    addTearDown(c.dispose);
    await c.read(routingPreviewProvider(_key).future);
    return c;
  }

  group('RoutingPreview.fromJson', () {
    test('parses groups, conflicts, requests, contacts and unrouted', () {
      final p = RoutingPreview.fromJson(_previewJson());

      expect(p.groups.map((g) => g.key), ['timeline', 'performance']);
      expect(p.allItems.length, 3);
      expect(p.allItems.first.targetLabel, 'First dance');
      expect(p.allItems.elementAt(1).defaultChecked, isFalse);
      // Omitted default_checked / status fall back to checked + pending.
      expect(p.allItems.last.defaultChecked, isTrue);
      expect(p.allItems.last.status, 'pending');

      expect(p.conflicts.length, 3);
      expect(p.knownConflicts.length, 2); // unknown kind is ignored
      expect(p.songRequests.mustPlay, 32);
      expect(p.songRequests.writeIns, ['Here for a Good Time']);
      expect(p.contacts.single.onBooking, isTrue);
      expect(p.unrouted.single.compatibleTargets.map((t) => t.key),
          ['wedding.toasts', 'performance.notes']);
      expect(p.unrouted.single.compatibleTargets.first.label, 'Toasts');
    });

    test('tolerates an empty payload and object-shaped targets', () {
      final p = RoutingPreview.fromJson({
        'song_requests': [], // empty PHP array serializes as []
        'unrouted': [
          {
            'response_id': 1,
            'compatible_targets': [
              {'key': 'wedding.colors', 'label': 'Colors', 'hint': 'Text'},
            ],
          },
        ],
      });
      expect(p.groups, isEmpty);
      expect(p.songRequests.isEmpty, isTrue);
      expect(p.unrouted.single.compatibleTargets.single.hint, 'Text');
    });

    test('item compatible_targets are optional; fallbacks are free-text only',
        () {
      final withTargets = RoutingItem.fromJson({
        'response_id': 1,
        'target': 'performance.notes',
        'compatible_targets': ['performance.notes', 'event.notes'],
      });
      expect(withTargets.compatibleTargets.map((t) => t.key),
          ['performance.notes', 'event.notes']);
      expect(RoutingItem.fromJson({'response_id': 2}).compatibleTargets,
          isEmpty);

      final keys = fallbackRoutingTargets.map((t) => t.key);
      expect(keys, isNot(contains('wedding.onsite')));
      expect(keys, contains('wedding.toasts'));
    });

    test('RouteResult parses application id, count and event', () {
      final r = RouteResult.fromJson({
        'application_id': 5,
        'applied': 12,
        'event': {'id': 3, 'key': 'abc'},
      });
      expect(r.applicationId, 5);
      expect(r.applied, 12);
      expect(r.eventId, 3);
      expect(r.eventKey, 'abc');
    });
  });

  group('routing providers', () {
    test('preview loads from the repository', () async {
      final repo = FakeQuestionnairesRepository()
        ..routingPreview = RoutingPreview.fromJson(_previewJson());
      final c = await loaded(repo);
      expect(c.read(routingPreviewProvider(_key)).value!.groups.length, 2);
    });

    test('a 404 (null preview) is the fallback signal', () async {
      final repo = FakeQuestionnairesRepository(); // routingPreview == null
      final c = await loaded(repo);
      expect(c.read(routingPreviewProvider(_key)).value, isNull);
      // Selection stays empty and harmless.
      expect(c.read(routingSelectionProvider(_key)).checked, isEmpty);
    });

    test('placeholder items start unchecked, others checked', () async {
      final repo = FakeQuestionnairesRepository()
        ..routingPreview = RoutingPreview.fromJson(_previewJson());
      final c = await loaded(repo);
      expect(c.read(routingSelectionProvider(_key)).checked, {1, 3});
    });

    test('toggle checks and unchecks an item', () async {
      final repo = FakeQuestionnairesRepository()
        ..routingPreview = RoutingPreview.fromJson(_previewJson());
      final c = await loaded(repo);
      final n = c.read(routingSelectionProvider(_key).notifier);

      n.toggle(2);
      expect(c.read(routingSelectionProvider(_key)).checked, contains(2));
      n.toggle(2);
      expect(c.read(routingSelectionProvider(_key)).checked, isNot(contains(2)));
    });

    test('unresolved conflicts are not counted until resolved', () async {
      final repo = FakeQuestionnairesRepository()
        ..routingPreview = RoutingPreview.fromJson(_previewJson());
      final c = await loaded(repo);
      final preview = c.read(routingPreviewProvider(_key)).value!;
      final n = c.read(routingSelectionProvider(_key).notifier);

      var sel = c.read(routingSelectionProvider(_key));
      expect(sel.unresolvedCount(preview), 2);
      expect(sel.sendCount(preview), 2); // items 1 and 3 only

      n.resolveSong(12, 'do_not_play');
      sel = c.read(routingSelectionProvider(_key));
      expect(sel.unresolvedCount(preview), 1);
      expect(sel.sendCount(preview), 3);

      n.resolveVenue('booking');
      sel = c.read(routingSelectionProvider(_key));
      expect(sel.unresolvedCount(preview), 0);
      expect(sel.sendCount(preview), 4);
    });

    test('send posts checked items, overrides and resolutions', () async {
      final repo = FakeQuestionnairesRepository()
        ..routingPreview = RoutingPreview.fromJson(_previewJson())
        ..routeResult = const RouteResult(
            applicationId: 41, applied: 4, event: {'id': 3, 'key': 'abc'});
      final c = await loaded(repo);
      final preview = c.read(routingPreviewProvider(_key)).value!;
      final n = c.read(routingSelectionProvider(_key).notifier);

      n.setTarget(9, 'wedding.toasts', remember: true); // unrouted pick
      n.setTarget(3, null); // "Don't send"
      n.resolveSong(12, 'do_not_play');
      // Venue left unresolved: must not be sent.

      final result = await n.send(preview);

      expect(result.applicationId, 41);
      expect(repo.routedItems, [
        {'response_id': 1, 'target': 'wedding.dance.first'},
        {'response_id': 9, 'target': 'wedding.toasts', 'remember': true},
      ]);
      expect(repo.routedResolutions, {
        'songs': {'12': 'do_not_play'},
      });
      final app = c.read(lastRoutedApplicationProvider)!;
      expect(app.applicationId, 41);
      expect(app.matches(id: 3, key: 'zzz'), isTrue);
      expect(app.matches(id: 99, key: 'zzz'), isFalse);
    });

    test('send records the application for the undo banner', () async {
      final repo = FakeQuestionnairesRepository()
        ..routingPreview = RoutingPreview.fromJson(_previewJson());
      final c = await loaded(repo);
      final preview = c.read(routingPreviewProvider(_key)).value!;
      await c.read(routingSelectionProvider(_key).notifier).send(preview);
      expect(c.read(lastRoutedApplicationProvider), isNotNull);
      // The band's cached events (and client picks) are dropped.
      expect(invalidator.appliedBands, [_key.bandId]);

      await repo.undoApplication(1, 9);
      expect(repo.undoneApplicationId, 9);
    });
  });

  group('contacts and new preview fields', () {
    test('contact parses email, phone and contact_id', () {
      final c = RoutingContact.fromJson({
        'name': 'Grace',
        'email': 'g@x.com',
        'phone': ' ',
        'on_booking': false,
        'contact_id': 4,
      });
      expect(c.email, 'g@x.com');
      expect(c.phone, isNull); // blank -> null
      expect(c.contactId, 4);
      expect(c.toAddContactBody(), {'contact_id': 4, 'role': ''});

      final fresh = RoutingContact.fromJson(
          {'name': 'Todd', 'email': 't@x.com', 'on_booking': false});
      expect(fresh.toAddContactBody(),
          {'name': 'Todd', 'email': 't@x.com', 'phone': '', 'role': ''});
    });

    test('song conflicts show Title · Artist; extra fields are tolerated', () {
      final p = RoutingPreview.fromJson({
        'event_id': 3,
        'conflicts': [
          {
            'kind': 'song_both_lists',
            'song_id': 12,
            'title': 'We Are Family',
            'artist': 'Sister Sledge',
          },
          {'kind': 'song_both_lists', 'song_id': 13, 'title': 'Solo'},
        ],
        'song_requests': {'do_not_play_write_ins': ['x']},
        'groups': [
          {
            'key': 'a',
            'label': 'A',
            'items': [
              {
                'response_id': 1,
                'field_type': 'long_text',
                'targets': [],
                'compatible_targets': [
                  {'key': 'event.notes', 'label': 'Event notes'},
                ],
              },
            ],
          },
        ],
      });
      expect(p.conflicts.first.songDisplay, 'We Are Family · Sister Sledge');
      expect(p.conflicts.last.songDisplay, 'Solo');
      expect(p.allItems.single.compatibleTargets.single.label, 'Event notes');
    });

    test('addContact posts to the booking contacts endpoint and refetches',
        () async {
      final adapter = _RecordingAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      final repo = FakeQuestionnairesRepository()
        ..routingPreview = RoutingPreview.fromJson(_previewJson());
      final c = ProviderContainer(overrides: [
        questionnairesRepositoryProvider.overrideWithValue(repo),
        bookingsRepositoryProvider.overrideWithValue(BookingsRepository(dio)),
        cacheInvalidatorProvider.overrideWithValue(invalidator),
      ]);
      addTearDown(c.dispose);
      await c.read(routingPreviewProvider(_key).future);
      // Hold the auto-dispose provider open, as the screen does.
      c.listen(routingSelectionProvider(_key), (_, __) {});
      final n = c.read(routingSelectionProvider(_key).notifier);
      n.toggle(2); // a user choice that must survive the refetch

      await n.addContact(
          const RoutingContact(
              name: 'Todd', email: 't@x.com', onBooking: false),
          55);

      final req = adapter.requests.single;
      expect(req.method, 'POST');
      expect(req.path, contains('/bands/1/bookings/55/contacts'));
      expect(req.data, containsPair('name', 'Todd'));
      expect(c.read(routingSelectionProvider(_key)).checked, contains(2));
    });
  });

  test('WeddingDetail parses colors and keeps toasts among dances', () {
    final w = WeddingDetail.fromJson({
      'onsite': true,
      'colors': ' Pink, green, white ',
      'dances': [
        {'title': 'Toasts', 'data': 'Paul Looney, father of the bride'},
      ],
    });
    expect(w.colors, 'Pink, green, white');
    expect(w.dances.single.title, 'Toasts');

    expect(WeddingDetail.fromJson({'dances': [], 'colors': ''}).colors, isNull);
    expect(WeddingDetail.fromJson({'dances': []}).colors, isNull);
  });
}
