import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_bandmate/core/network/pusher_connection.dart';
import 'package:tts_bandmate/core/providers/core_providers.dart';
import 'package:tts_bandmate/features/setlist/providers/live_session_provider.dart';
import 'package:tts_bandmate/shared/cache/api_cache_storage.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';

import '../../helpers/test_harness.dart';

// Pick-as-you-go (dynamic) sessions: the captain starts with no setlist and
// picks each song live.

const _eventKey = 'evt-1';
const _sessionPath = '/api/mobile/setlist/events/$_eventKey/session';

Map<String, dynamic> _entry(int id, int position, String status) => {
      'id': id,
      'type': 'song',
      'song_id': id,
      'position': position,
      'status': status,
      'title': 'Song $id',
    };

Map<String, dynamic> _payload({
  required int currentPosition,
  required List<Map<String, dynamic>> queue,
  bool isDynamic = true,
  Map<String, dynamic>? clientRequests,
  Map<String, dynamic>? clientNotes,
}) =>
    {
      'session': {
        'id': 9,
        'status': 'active',
        'is_dynamic': isDynamic,
        'current_position': currentPosition,
        'queue': queue,
        'captains': [],
      },
      'songs': [
        {'id': 1, 'title': 'Song 1'},
        {'id': 2, 'title': 'Song 2'},
      ],
      'client_requests': clientRequests,
      'client_notes': clientNotes,
      'is_captain': true,
      'can_write': true,
      'current_user_id': 5,
    };

class _FakeSelectedBand extends AsyncNotifier<int?>
    implements SelectedBandNotifier {
  @override
  Future<int?> build() async => 1;

  @override
  Future<void> selectBand(int id) async {}

  @override
  Future<void> clear() async {}
}

Future<ProviderContainer> _container(
  List<Map<String, dynamic>> sessionResponses,
  List<String> calls, {
  List<int>? addedSongIds,
  List<bool>? appended,
  void Function(Object? body)? onBody,
  Map<String, dynamic>? suggestion,
  List<Map<String, dynamic>>? suggestQueries,
}) async {
  SharedPreferences.setMockInitialValues({});
  final cache = ApiCacheStorage(await SharedPreferences.getInstance());
  var getCount = 0;
  final dio = Dio()
    ..httpClientAdapter = StubAdapter((options) async {
      calls.add('${options.method} ${options.path}');
      if (options.method == 'PUT') onBody?.call(options.data);
      if (options.method == 'GET' && options.path == _sessionPath) {
        final i = getCount < sessionResponses.length
            ? getCount
            : sessionResponses.length - 1;
        getCount++;
        return json(200, sessionResponses[i]);
      }
      if (options.path.endsWith('/suggest')) {
        suggestQueries?.add(Map.of(options.queryParameters));
        return json(200, {'suggestion': suggestion});
      }
      if (options.path.endsWith('/off-setlist')) {
        final body = options.data as Map;
        addedSongIds?.add(body['song_id'] as int);
        appended?.add(body['placement'] == 'end');
        return json(200, {'id': 2, 'title': 'Song 2', 'artist': null});
      }
      return json(200, {'ok': true});
    });
  final container = ProviderContainer(overrides: [
    apiClientProvider.overrideWithValue(
        StubApiClient(storage: FakeSecureStorage(), dio: dio)),
    apiCacheStorageProvider.overrideWithValue(cache),
    selectedBandProvider.overrideWith(() => _FakeSelectedBand()),
    // No token → realtime unavailable, no native Pusher calls.
    pusherConnectionProvider
        .overrideWithValue(PusherConnection(() async => null)),
  ]);
  await container.read(selectedBandProvider.future);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('picking a song when nothing is playing starts it immediately',
      () async {
    final calls = <String>[];
    final container = await _container([
      _payload(currentPosition: 1, queue: []),
    ], calls);
    addTearDown(container.dispose);
    final notifier = container.read(liveSessionProvider(_eventKey).notifier);
    await notifier.load();
    calls.clear();

    await notifier.addOffSetlist(2);

    expect(calls, [
      'POST /api/mobile/setlist/sessions/9/off-setlist',
      'POST /api/mobile/setlist/sessions/9/next',
      'GET $_sessionPath',
    ]);
  });

  test('picking a song while one is playing only queues it', () async {
    final calls = <String>[];
    final container = await _container([
      _payload(currentPosition: 1, queue: [_entry(1, 1, 'pending')]),
    ], calls);
    addTearDown(container.dispose);
    final notifier = container.read(liveSessionProvider(_eventKey).notifier);
    await notifier.load();
    calls.clear();

    await notifier.addOffSetlist(2);

    expect(calls, [
      'POST /api/mobile/setlist/sessions/9/off-setlist',
      'GET $_sessionPath',
    ]);
  });

  test('pick-as-you-go: first pick plays, the rest append in pick order',
      () async {
    final calls = <String>[];
    final added = <int>[];
    final appended = <bool>[];
    final container = await _container([
      _payload(currentPosition: 1, queue: []),
    ], calls, addedSongIds: added, appended: appended);
    addTearDown(container.dispose);
    final notifier = container.read(liveSessionProvider(_eventKey).notifier);
    await notifier.load();
    calls.clear();

    await notifier.addSongs([1, 2, 3]);

    expect(added, [1, 2, 3]);
    expect(appended, [true, true, true]);
    expect(calls.where((c) => c.endsWith('/next')), hasLength(1));
    expect(calls.indexOf('POST /api/mobile/setlist/sessions/9/next'), 1);
  });

  test('pick-as-you-go: picks while a song plays append to the end',
      () async {
    final calls = <String>[];
    final added = <int>[];
    final appended = <bool>[];
    final container = await _container([
      _payload(currentPosition: 1, queue: [_entry(1, 1, 'pending')]),
    ], calls, addedSongIds: added, appended: appended);
    addTearDown(container.dispose);
    final notifier = container.read(liveSessionProvider(_eventKey).notifier);
    await notifier.load();
    calls.clear();

    await notifier.addSongs([2, 3]);

    expect(added, [2, 3]);
    expect(appended, [true, true]);
    expect(calls.where((c) => c.endsWith('/next')), isEmpty);
  });

  test('setlist session: picks slot in right after the current song, in order',
      () async {
    final calls = <String>[];
    final added = <int>[];
    final appended = <bool>[];
    final container = await _container([
      _payload(
          currentPosition: 1,
          queue: [_entry(1, 1, 'pending')],
          isDynamic: false),
    ], calls, addedSongIds: added, appended: appended);
    addTearDown(container.dispose);
    final notifier = container.read(liveSessionProvider(_eventKey).notifier);
    await notifier.load();

    await notifier.addSongs([2, 3]);

    // Each insert lands directly after the current song, so reverse order
    // leaves 2 then 3 queued next.
    expect(added, [3, 2]);
    expect(appended, [false, false]);
  });

  test('songs already queued or played are never added again', () async {
    final calls = <String>[];
    final added = <int>[];
    final container = await _container([
      _payload(currentPosition: 2, queue: [
        _entry(1, 1, 'played'),
        _entry(2, 2, 'pending'),
      ]),
    ], calls, addedSongIds: added);
    addTearDown(container.dispose);
    final notifier = container.read(liveSessionProvider(_eventKey).notifier);
    await notifier.load();
    calls.clear();

    await notifier.addSongs([1, 2, 3, 3]);

    expect(added, [3]);

    added.clear();
    calls.clear();
    await notifier.addSongs([1, 2]);
    expect(added, isEmpty);
    expect(calls, isEmpty);
  });

  test('removing an upcoming song drops it and calls the server', () async {
    final calls = <String>[];
    final container = await _container([
      _payload(currentPosition: 1, queue: [
        _entry(1, 1, 'pending'),
        _entry(2, 2, 'pending'),
        _entry(3, 3, 'pending'),
      ]),
      _payload(currentPosition: 1, queue: [
        _entry(1, 1, 'pending'),
        _entry(3, 3, 'pending'),
      ]),
    ], calls);
    addTearDown(container.dispose);
    final notifier = container.read(liveSessionProvider(_eventKey).notifier);
    await notifier.load();
    calls.clear();

    final pending = notifier.removeUpcoming(2);
    // Gone immediately, before the server answers.
    expect(
      container
          .read(liveSessionProvider(_eventKey))
          .session!
          .queue
          .map((e) => e.id),
      [1, 3],
    );
    await pending;

    expect(calls, [
      'DELETE /api/mobile/setlist/sessions/9/queue/2',
      'GET $_sessionPath',
    ]);
    expect(
      container
          .read(liveSessionProvider(_eventKey))
          .session!
          .queue
          .map((e) => e.id),
      [1, 3],
    );
  });

  test('reordering upcoming applies locally and sends the full new order',
      () async {
    final calls = <String>[];
    Object? sentBody;
    final container = await _container([
      _payload(currentPosition: 1, queue: [
        _entry(1, 1, 'pending'), // playing
        _entry(2, 2, 'pending'),
        _entry(3, 3, 'pending'),
        _entry(4, 4, 'pending'),
      ]),
    ], calls, onBody: (b) => sentBody = b);
    addTearDown(container.dispose);
    final notifier = container.read(liveSessionProvider(_eventKey).notifier);
    await notifier.load();

    // Drag the last upcoming song (4) to the top of Upcoming.
    final pending = notifier.reorderUpcoming(2, 0);
    final order = container
        .read(liveSessionProvider(_eventKey))
        .session!
        .upcoming
        .map((e) => e.id);
    expect(order, [4, 2, 3]);
    await pending;

    expect(calls, contains('PUT /api/mobile/setlist/sessions/9/queue/order'));
    expect(sentBody, {
      'entry_ids': [4, 2, 3],
    });
  });

  test("the client's do-not-play songs are never added", () async {
    final calls = <String>[];
    final added = <int>[];
    final container = await _container([
      _payload(
        currentPosition: 1,
        queue: [_entry(1, 1, 'pending')],
        clientRequests: {
          'must_play': [],
          'do_not_play': [2],
        },
      ),
    ], calls, addedSongIds: added);
    addTearDown(container.dispose);
    final notifier = container.read(liveSessionProvider(_eventKey).notifier);
    await notifier.load();

    await notifier.addSongs([2, 3]);

    expect(added, [3]);
  });

  test('"another" skips songs already shown, without rejecting them',
      () async {
    final calls = <String>[];
    final queries = <Map<String, dynamic>>[];
    final container = await _container([
      _payload(currentPosition: 1, queue: [_entry(1, 1, 'pending')]),
    ], calls,
        suggestion: {'song_id': 7, 'title': 'Shout', 'must_play': true},
        suggestQueries: queries);
    addTearDown(container.dispose);
    final notifier = container.read(liveSessionProvider(_eventKey).notifier);
    await notifier.load();

    await notifier.suggestNext();
    final first = container.read(liveSessionProvider(_eventKey)).suggestion;
    expect(first?.songId, 7);
    expect(first?.mustPlay, isTrue);

    await notifier.suggestNext(another: true);
    await notifier.suggestNext(another: true);

    expect(queries, [
      <String, dynamic>{},
      {
        'skip[]': [7],
      },
      // The stub keeps answering 7; it's only listed once.
      {
        'skip[]': [7],
      },
    ]);

    // Asking fresh starts a new round.
    await notifier.suggestNext();
    expect(queries.last, <String, dynamic>{});
  });

  test('queuing a suggestion after the queue ran out starts it', () async {
    final calls = <String>[];
    final container = await _container([
      // Last song finished, nothing playing.
      _payload(currentPosition: 1, queue: [_entry(1, 1, 'played')]),
      // After accepting: appended behind it.
      _payload(currentPosition: 1, queue: [
        _entry(1, 1, 'played'),
        _entry(7, 2, 'pending'),
      ]),
      _payload(currentPosition: 2, queue: [
        _entry(1, 1, 'played'),
        _entry(7, 2, 'pending'),
      ]),
    ], calls, suggestion: {'song_id': 7, 'title': 'Shout'});
    addTearDown(container.dispose);
    final notifier = container.read(liveSessionProvider(_eventKey).notifier);
    await notifier.load();
    await notifier.suggestNext();
    calls.clear();

    await notifier.acceptSuggestion();

    expect(calls, [
      'POST /api/mobile/setlist/sessions/9/accept-suggestion',
      'GET $_sessionPath',
      'POST /api/mobile/setlist/sessions/9/next',
      'GET $_sessionPath',
    ]);
    expect(
        container
            .read(liveSessionProvider(_eventKey))
            .session!
            .currentSong
            ?.songId,
        7);
  });

  test('a request not in the catalog is queued by title, at the end',
      () async {
    final calls = <String>[];
    Object? body;
    final container = await _container([
      _payload(currentPosition: 1, queue: [_entry(1, 1, 'pending')]),
    ], calls);
    addTearDown(container.dispose);
    final notifier = container.read(liveSessionProvider(_eventKey).notifier);
    await notifier.load();
    calls.clear();

    // Capture the POST body through the off-setlist stub.
    final dio = container.read(apiClientProvider).dio;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      if (o.path.endsWith('/off-setlist')) body = o.data;
      h.next(o);
    }));

    await notifier.addCustomSong('Calling Baton Rouge', artist: 'Garth Brooks');

    expect(body, {
      'custom_title': 'Calling Baton Rouge',
      'custom_artist': 'Garth Brooks',
      'placement': 'end',
    });
  });

  test('do-not-play songs from the free text are blocked too', () async {
    final calls = <String>[];
    final added = <int>[];
    final container = await _container([
      _payload(
        currentPosition: 1,
        queue: [_entry(1, 1, 'pending')],
        clientNotes: {
          'requests': [
            {'title': 'Song 2', 'song_id': 2, 'kind': 'do_not_play'},
          ],
        },
      ),
    ], calls, addedSongIds: added);
    addTearDown(container.dispose);
    final notifier = container.read(liveSessionProvider(_eventKey).notifier);
    await notifier.load();

    await notifier.addSongs([2, 3]);

    expect(added, [3]);
  });

  test('reacting shows immediately; tapping the same reaction clears it',
      () async {
    final calls = <String>[];
    final bodies = <Object?>[];
    final container = await _container([
      _payload(currentPosition: 1, queue: [_entry(1, 1, 'pending')]),
    ], calls);
    addTearDown(container.dispose);
    final notifier = container.read(liveSessionProvider(_eventKey).notifier);
    await notifier.load();
    container.read(apiClientProvider).dio.interceptors.add(
        InterceptorsWrapper(onRequest: (o, h) {
      if (o.path.endsWith('/reaction')) bodies.add(o.data);
      h.next(o);
    }));

    final pending = notifier.react(1, 'positive');
    expect(
      container
          .read(liveSessionProvider(_eventKey))
          .session!
          .currentSong!
          .crowdReaction,
      'positive',
    );
    await pending;

    // The stub's resync doesn't echo the reaction, so seed it before the
    // second tap to model the server state.
    notifier.state = notifier.state.copyWith(
      session: () => notifier.state.session!.copyWith(queue: [
        notifier.state.session!.queue.single
            .copyWith(crowdReaction: () => 'positive'),
      ]),
    );
    await notifier.react(1, 'positive');

    expect(bodies, [
      {'queue_entry_id': 1, 'reaction': 'positive'},
      {'queue_entry_id': 1, 'reaction': 'neutral'},
    ]);
  });

  test('a suggested client request outside the catalog: skip by title, queue by title',
      () async {
    final calls = <String>[];
    final queries = <Map<String, dynamic>>[];
    Object? offSetlistBody;
    final container = await _container([
      _payload(currentPosition: 1, queue: [_entry(1, 1, 'pending')]),
    ], calls,
        suggestion: {
          'song_id': null,
          'custom': true,
          'must_play': true,
          'title': 'Calling Baton Rouge',
          'artist': 'Garth Brooks',
          'note': 'Bride is Samantha',
        },
        suggestQueries: queries);
    addTearDown(container.dispose);
    final notifier = container.read(liveSessionProvider(_eventKey).notifier);
    await notifier.load();
    container.read(apiClientProvider).dio.interceptors.add(
        InterceptorsWrapper(onRequest: (o, h) {
      if (o.path.endsWith('/off-setlist')) offSetlistBody = o.data;
      h.next(o);
    }));

    await notifier.suggestNext();
    final s = container.read(liveSessionProvider(_eventKey)).suggestion!;
    expect(s.isCustom, isTrue);
    expect(s.note, 'Bride is Samantha');

    await notifier.suggestNext(another: true);
    expect(queries.last, {
      'skip_titles[]': ['Calling Baton Rouge'],
    });

    await notifier.acceptSuggestion();
    expect(calls.where((c) => c.endsWith('/accept-suggestion')), isEmpty);
    expect(offSetlistBody, {
      'custom_title': 'Calling Baton Rouge',
      'custom_artist': 'Garth Brooks',
      'placement': 'end',
    });
  });

  test('captain actions re-sync even without realtime updates', () async {
    final calls = <String>[];
    final container = await _container([
      _payload(currentPosition: 1, queue: []),
      _payload(currentPosition: 2, queue: [_entry(2, 2, 'pending')]),
    ], calls);
    addTearDown(container.dispose);
    final notifier = container.read(liveSessionProvider(_eventKey).notifier);
    await notifier.load();

    await notifier.addOffSetlist(2);

    final current = container
        .read(liveSessionProvider(_eventKey))
        .session!
        .currentSong;
    expect(current?.songId, 2);
  });

  test('Next on the last song re-syncs so nothing shows as playing',
      () async {
    final calls = <String>[];
    final container = await _container([
      _payload(currentPosition: 1, queue: [_entry(1, 1, 'pending')]),
      _payload(currentPosition: 1, queue: [_entry(1, 1, 'played')]),
    ], calls);
    addTearDown(container.dispose);
    final notifier = container.read(liveSessionProvider(_eventKey).notifier);
    await notifier.load();
    expect(
        container.read(liveSessionProvider(_eventKey)).session!.currentSong,
        isNotNull);

    await notifier.next();

    final session = container.read(liveSessionProvider(_eventKey)).session!;
    expect(session.currentSong, isNull);
    expect(session.queue.single.isPlayed, isTrue);
  });
}
