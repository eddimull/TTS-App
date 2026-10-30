import 'package:clock/clock.dart';
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/events/data/event_music.dart';
import 'package:tts_bandmate/features/events/data/models/event_detail.dart';
import 'package:tts_bandmate/features/events/providers/event_music_provider.dart';
import 'package:tts_bandmate/features/events/providers/events_provider.dart';
import 'package:tts_bandmate/features/events/screens/event_music_screen.dart';
import 'package:tts_bandmate/features/library/data/models/chart.dart';
import 'package:tts_bandmate/features/library/providers/library_provider.dart';
import 'package:tts_bandmate/features/rehearsals/data/models/rehearsal_detail.dart';
import 'package:tts_bandmate/features/rehearsals/data/models/rehearsal_schedule.dart';
import 'package:tts_bandmate/features/rehearsals/data/rehearsals_repository.dart';
import 'package:tts_bandmate/features/setlist_editor/data/models/event_setlist.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';

const _key = 'evt';

final _event = EventDetail.fromJson({
  'id': 1,
  'key': _key,
  'title': 'Terreson Wedding',
  'date': '2026-11-07',
  'can_write': true,
  'members': <dynamic>[],
  'wedding': {
    'dances': [
      {'title': 'first_dance', 'data': 'Forever and Ever, Amen'},
      {'title': 'mother_son', 'data': 'TBD'},
    ],
  },
  'performance': {
    'notes': 'Upbeat only',
    'songs': [
      {'title': 'Forever and Ever Amen', 'url': 'https://example.com/ffa'},
    ],
    'charts': [
      {'title': 'Haterz', 'composer': 'Horns'},
    ],
  },
});

final _music = const EventMusic(
  bandSongs: [
    BandSongSummary(
        id: 7,
        title: 'Forever and Ever, Amen',
        artist: 'Randy Travis',
        songKey: 'E',
        bpm: 72,
        leadSinger: 'Jake'),
    BandSongSummary(id: 8, title: 'September'),
  ],
  requests: ClientSongRequests(mustPlayIds: {8}, doNotPlayIds: {}),
  setlist: EventSetlist(id: 1, status: 'ready', songs: [
    SetlistEntry(type: 'song', position: 1, songId: 8, title: 'September'),
    SetlistEntry(
        type: 'song',
        position: 2,
        customTitle: 'Here for a Good Time',
        customArtist: 'George Strait'),
    SetlistEntry(type: 'break', position: 3),
    SetlistEntry(type: 'song', position: 4, customTitle: 'Boogie Wonderland'),
  ]),
);

class _FakeDetail extends EventDetailNotifier {
  _FakeDetail() : super(_key);
  @override
  Future<EventDetail> build() async => _event;
}

class _FakeBand extends SelectedBandNotifier {
  @override
  Future<int?> build() async => 1;
}

class _FakeLibrary extends LibraryNotifier {
  @override
  Future<LibraryState> build() async => LibraryState(charts: [
        Chart.fromJson({
          'id': 40,
          'band_id': 1,
          'title': 'Forever and Ever (E)',
          'song': {'id': 7, 'title': 'Forever and Ever, Amen'},
        }),
      ]);
}

Map<String, dynamic> _detailJson(int id, String? notes) => {
      'id': id,
      'date': '2026-11-03',
      'time': '19:00',
      'notes': notes,
      'schedule': {'id': 1, 'name': 'Weekly'},
    };

class _FakeRehearsals extends RehearsalsRepository {
  _FakeRehearsals(this.rehearsals) : super(Dio());
  final List<Map<String, dynamic>> rehearsals;
  String? notes = 'Bring the PA';
  final saved = <(int, String?)>[];
  final resolvedKeys = <String>[];

  @override
  Future<List<RehearsalSchedule>> getSchedules(int bandId,
          {String? until, bool includeVirtual = false}) async =>
      [
        RehearsalSchedule.fromJson({
          'id': 1,
          'name': 'Weekly',
          'upcoming_rehearsals': rehearsals,
        }),
      ];

  @override
  Future<RehearsalDetail> getRehearsalDetail(int rehearsalId) async =>
      RehearsalDetail.fromJson(_detailJson(rehearsalId, notes));

  @override
  Future<RehearsalDetail> getRehearsalByKey(String key) async {
    resolvedKeys.add(key);
    return RehearsalDetail.fromJson(_detailJson(99, notes));
  }

  @override
  Future<String?> updateNotes(int rehearsalId, String? notes) async {
    saved.add((rehearsalId, notes));
    this.notes = notes;
    return notes;
  }
}

Future<_FakeRehearsals> _pump(
  WidgetTester tester, {
  List<Map<String, dynamic>> rehearsals = const [
    {'id': 5, 'date': '2026-11-03', 'time': '19:00'},
  ],
}) async {
  tester.view.physicalSize = const Size(400, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final repo = _FakeRehearsals(rehearsals);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      eventDetailProvider(_key).overrideWith(_FakeDetail.new),
      eventMusicProvider.overrideWith((ref, key) async => _music),
      selectedBandProvider.overrideWith(_FakeBand.new),
      rehearsalsRepositoryProvider.overrideWithValue(repo),
      libraryProvider.overrideWith(_FakeLibrary.new),
    ],
    child: const CupertinoApp(home: EventMusicScreen(eventKey: _key)),
  ));
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  final now = DateTime(2026, 10, 30, 9);

  testWidgets('shows each section with jump chips', (tester) async {
    await withClock(Clock.fixed(now), () async {
      await _pump(tester);
      for (final chip in ['To learn 2', 'Dances', 'Requests', 'Charts']) {
        expect(find.text(chip), findsOneWidget, reason: chip);
      }
      // The Setlist chip and the section header.
      expect(find.text('Setlist'), findsNWidgets(2));
      expect(find.text('Here for a Good Time'), findsOneWidget);
      expect(find.text('Not in catalog · George Strait'), findsOneWidget);
      // Dances without a song are left out.
      expect(find.text('Forever and Ever, Amen'), findsOneWidget);
      expect(find.text('Mother son'), findsNothing);
      expect(find.text('1 of the 1 must-plays are on the setlist.'),
          findsOneWidget);
      expect(find.text('Ready'), findsOneWidget);
      expect(find.text('3 songs'), findsOneWidget);
      expect(find.text('Set 1'), findsOneWidget);
      expect(find.text('Set 2'), findsOneWidget);
      expect(find.text('Open setlist editor'), findsOneWidget);
      expect(find.text('Haterz'), findsOneWidget);
    });
  });

  testWidgets('adds the songs to learn to the next rehearsal', (tester) async {
    await withClock(Clock.fixed(now), () async {
      final repo = await _pump(tester);
      expect(
          find.textContaining('1 rehearsal before this gig',
              findRichText: true),
          findsOneWidget);
      await tester.tap(find.text('Add to rehearsal'));
      await tester.pumpAndSettle();

      expect(repo.saved.single.$1, 5);
      expect(
          repo.saved.single.$2,
          'Bring the PA\nLearn for Terreson Wedding (Nov 7): '
          'Here for a Good Time, Boogie Wonderland');
      expect(find.text('Added 2 songs to Tue, Nov 3, 7:00 PM'), findsOneWidget);

      // A second tap finds them already there and writes nothing.
      await tester.tap(find.text('Add to rehearsal'));
      await tester.pumpAndSettle();
      expect(repo.saved, hasLength(1));
      expect(find.text('Already in the notes for Tue, Nov 3, 7:00 PM'),
          findsOneWidget);
    });
  });

  testWidgets('a virtual rehearsal is created through its key', (tester) async {
    await withClock(Clock.fixed(now), () async {
      final repo = await _pump(tester, rehearsals: [
        {
          'date': '2026-11-03',
          'time': '19:00',
          'is_virtual': true,
          'event_key': 'sched-1-2026-11-03'
        },
      ]);
      await tester.tap(find.text('Add to rehearsal'));
      await tester.pumpAndSettle();
      expect(repo.resolvedKeys, ['sched-1-2026-11-03']);
      expect(repo.saved.single.$1, 99);
    });
  });

  testWidgets('no rehearsal before the gig hides the button', (tester) async {
    await withClock(Clock.fixed(now), () async {
      await _pump(tester, rehearsals: const []);
      expect(find.text('No rehearsal before this gig'), findsOneWidget);
      expect(find.text('Add to rehearsal'), findsNothing);
    });
  });

  testWidgets('song sheet for a dance shows catalog details and chart',
      (tester) async {
    await withClock(Clock.fixed(now), () async {
      final repo = await _pump(tester);
      await tester.tap(find.text('Forever and Ever, Amen'));
      await tester.pumpAndSettle();

      expect(find.text('Randy Travis · First dance'), findsOneWidget);
      expect(find.text('E'), findsOneWidget);
      expect(find.text('72'), findsOneWidget);
      expect(find.text('Jake'), findsOneWidget);
      expect(find.text('Chart · Forever and Ever (E)'), findsOneWidget);
      expect(find.text('Reference recording'), findsOneWidget);
      expect(
          find.text(
              'Adds it to Tue, Nov 3, 7:00 PM · the next rehearsal before this gig'),
          findsOneWidget);

      // The sheet's button, above the page's.
      await tester.tap(find.text('Add to rehearsal').last);
      await tester.pumpAndSettle();
      expect(
          repo.saved.single.$2,
          endsWith(
              'Learn for Terreson Wedding (Nov 7): Forever and Ever, Amen'));
      expect(find.text('Added to Tue, Nov 3, 7:00 PM'), findsOneWidget);
    });
  });

  testWidgets('song sheet for a song to learn says there is no chart',
      (tester) async {
    await withClock(Clock.fixed(now), () async {
      await _pump(tester);
      // The To learn row (the setlist preview also names it).
      await tester.tap(find.text('Boogie Wonderland').first);
      await tester.pumpAndSettle();
      expect(find.text('Not in our catalog'), findsWidgets);
      expect(find.text('No chart or recording yet'), findsOneWidget);
    });
  });
}
