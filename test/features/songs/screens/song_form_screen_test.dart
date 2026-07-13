import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/personnel/data/models/roster.dart';
import 'package:tts_bandmate/features/songs/data/models/song.dart';
import 'package:tts_bandmate/features/songs/data/songs_repository.dart';
import 'package:tts_bandmate/features/songs/providers/songs_provider.dart';
import 'package:tts_bandmate/features/songs/screens/song_form_screen.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';

class _StubBand extends SelectedBandNotifier {
  @override
  Future<int?> build() async => 1;
}

class _FakeRepo implements SongsRepository {
  Song? lastCreatedDraft;
  Song? lastUpdated;
  Map<String, dynamic> lookupResult = const {'bpm': 100, 'song_key': 'E♭m'};

  @override
  Future<({List<Song> songs, List<String> genres})> getSongs(
    int bandId, {
    bool includeInactive = false,
  }) async =>
      (
        songs: const [Song(id: 50, bandId: 1, title: 'Existing Tune')],
        genres: const ['Funk', 'Soul'],
      );

  @override
  Future<Song> createSong(int bandId, Song song) async {
    lastCreatedDraft = song;
    return Song(id: 999, bandId: bandId, title: song.title, bpm: song.bpm);
  }

  @override
  Future<Song> updateSong(int bandId, Song song) async {
    lastUpdated = song;
    return song;
  }

  @override
  Future<Map<String, dynamic>> lookupBpm({
    required String title,
    String? artist,
  }) async =>
      lookupResult;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// The form pops with the saved Song, so it must sit above a base route —
/// popping the root route of a test app is undefined behaviour.
Widget _harness(_FakeRepo repo, {Song? existing}) => ProviderScope(
      overrides: [
        selectedBandProvider.overrideWith(_StubBand.new),
        songsRepositoryProvider.overrideWithValue(repo),
        leadSingerOptionsProvider.overrideWith(
          (ref) => Future.value(const <RosterMember>[]),
        ),
      ],
      child: CupertinoApp(
        home: CupertinoPageScaffold(
          child: Center(
            child: Builder(
              builder: (context) => CupertinoButton(
                onPressed: () => Navigator.of(context).push(
                  CupertinoPageRoute<Song>(
                    builder: (_) => SongFormScreen(existing: existing),
                  ),
                ),
                child: const Text('open form'),
              ),
            ),
          ),
        ),
      ),
    );

/// Pumps the harness and navigates into the form.
Future<void> _openForm(WidgetTester tester, _FakeRepo repo,
    {Song? existing}) async {
  await tester.pumpWidget(_harness(repo, existing: existing));
  await tester.pumpAndSettle();
  await tester.tap(find.text('open form'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Save is disabled until a title is entered', (tester) async {
    await _openForm(tester, _FakeRepo());

    final saveButton = find.widgetWithText(CupertinoButton, 'Save');
    expect(tester.widget<CupertinoButton>(saveButton).onPressed, isNull);

    await tester.enterText(
        find.widgetWithText(CupertinoTextField, 'Required'), 'September');
    await tester.pumpAndSettle();

    expect(tester.widget<CupertinoButton>(saveButton).onPressed, isNotNull);
  });

  testWidgets('saving a new song sends the entered fields', (tester) async {
    final repo = _FakeRepo();
    await _openForm(tester, repo);

    await tester.enterText(
        find.widgetWithText(CupertinoTextField, 'Required'), 'September');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(repo.lastCreatedDraft!.title, 'September');
    expect(repo.lastCreatedDraft!.active, true);
  });

  testWidgets('edit mode prefills fields and updates via updateSong',
      (tester) async {
    final repo = _FakeRepo();
    const existing = Song(
      id: 7,
      bandId: 1,
      title: 'Old Title',
      artist: 'EWF',
      bpm: 126,
      rating: 8,
    );
    await _openForm(tester, repo, existing: existing);

    expect(find.text('Edit Song'), findsOneWidget);
    expect(find.text('Old Title'), findsOneWidget);
    expect(find.text('EWF'), findsOneWidget);

    await tester.enterText(find.text('Old Title'), 'New Title');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(repo.lastUpdated!.id, 7);
    expect(repo.lastUpdated!.title, 'New Title');
    expect(repo.lastUpdated!.rating, 8);
  });

  testWidgets('Look up fills BPM and an empty key field', (tester) async {
    final repo = _FakeRepo();
    await _openForm(tester, repo);

    await tester.enterText(
        find.widgetWithText(CupertinoTextField, 'Required'), 'Superstition');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Look up'));
    await tester.pumpAndSettle();

    expect(find.text('100'), findsOneWidget);
    expect(find.text('E♭m'), findsOneWidget);
  });

  testWidgets('rating stepper increments from unset to 1', (tester) async {
    await _openForm(tester, _FakeRepo());

    await tester.tap(find.bySemanticsLabel('Increase Rating'));
    await tester.pumpAndSettle();

    expect(find.text('1 / 10'), findsOneWidget);
  });
}
