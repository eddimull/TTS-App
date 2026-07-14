import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/songs/data/models/song.dart';
import 'package:tts_bandmate/features/songs/data/songs_repository.dart';
import 'package:tts_bandmate/features/songs/providers/songs_provider.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';

class _FakeRepo implements SongsRepository {
  _FakeRepo({this.songs = const [], this.genres = const []});

  List<Song> songs;
  List<String> genres;
  Song? lastCreated;
  Song? lastUpdated;
  int? lastDeletedSongId;
  bool? lastIncludeInactive;

  @override
  Future<({List<Song> songs, List<String> genres})> getSongs(
    int bandId, {
    bool includeInactive = false,
  }) async {
    lastIncludeInactive = includeInactive;
    return (songs: songs, genres: genres);
  }

  @override
  Future<Song> createSong(int bandId, Song song) async {
    final created = Song(
      id: 999,
      bandId: bandId,
      title: song.title,
      artist: song.artist,
      active: song.active,
    );
    lastCreated = created;
    return created;
  }

  @override
  Future<Song> updateSong(int bandId, Song song) async {
    lastUpdated = song;
    return song;
  }

  @override
  Future<void> deleteSong(int bandId, int songId) async {
    lastDeletedSongId = songId;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _StubBandNotifier extends SelectedBandNotifier {
  _StubBandNotifier(this._id);
  final int? _id;
  @override
  Future<int?> build() async => _id;
}

ProviderContainer _container(_FakeRepo repo, {int? bandId = 1}) {
  final container = ProviderContainer(overrides: [
    songsRepositoryProvider.overrideWithValue(repo),
    selectedBandProvider.overrideWith(() => _StubBandNotifier(bandId)),
  ]);
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('build fetches all songs (include_inactive) sorted by title', () async {
    final repo = _FakeRepo(
      songs: const [
        Song(id: 2, bandId: 1, title: 'Zebra'),
        Song(id: 1, bandId: 1, title: 'apple', active: false),
      ],
      genres: const ['Funk'],
    );
    final container = _container(repo);

    final state = await container.read(songsProvider.future);

    expect(repo.lastIncludeInactive, true);
    expect(state.songs.map((s) => s.title).toList(), ['apple', 'Zebra']);
    expect(state.genres, ['Funk']);
  });

  test('build returns empty state when no band is selected', () async {
    final repo = _FakeRepo();
    final container = _container(repo, bandId: null);

    final state = await container.read(songsProvider.future);

    expect(state.songs, isEmpty);
    expect(repo.lastIncludeInactive, isNull);
  });

  test('createSong inserts the created song sorted', () async {
    final repo = _FakeRepo(songs: const [Song(id: 1, bandId: 1, title: 'Middle')]);
    final container = _container(repo);
    await container.read(songsProvider.future);

    final created = await container
        .read(songsProvider.notifier)
        .createSong(const Song(id: 0, bandId: 1, title: 'Apple'));

    expect(created.id, 999);
    final state = container.read(songsProvider).value!;
    expect(state.songs.map((s) => s.title).toList(), ['Apple', 'Middle']);
  });

  test('updateSong replaces the matching song and re-sorts', () async {
    final repo = _FakeRepo(songs: const [
      Song(id: 1, bandId: 1, title: 'Apple'),
      Song(id: 2, bandId: 1, title: 'Middle'),
    ]);
    final container = _container(repo);
    await container.read(songsProvider.future);

    await container
        .read(songsProvider.notifier)
        .updateSong(const Song(id: 1, bandId: 1, title: 'Zebra'));

    final state = container.read(songsProvider).value!;
    expect(state.songs.map((s) => s.title).toList(), ['Middle', 'Zebra']);
    expect(repo.lastUpdated!.title, 'Zebra');
  });

  test('deleteSong removes locally and calls the repository', () async {
    final repo = _FakeRepo(songs: const [
      Song(id: 1, bandId: 1, title: 'Apple'),
      Song(id: 2, bandId: 1, title: 'Middle'),
    ]);
    final container = _container(repo);
    await container.read(songsProvider.future);

    await container.read(songsProvider.notifier).deleteSong(1);

    final state = container.read(songsProvider).value!;
    expect(state.songs.map((s) => s.id).toList(), [2]);
    expect(repo.lastDeletedSongId, 1);
  });

  test('bandSongsProvider fetches songs for an explicit band', () async {
    final repo = _FakeRepo(songs: const [Song(id: 5, bandId: 3, title: 'Only')]);
    final container = _container(repo);

    final songs = await container.read(bandSongsProvider(3).future);

    expect(songs.single.title, 'Only');
  });
}
