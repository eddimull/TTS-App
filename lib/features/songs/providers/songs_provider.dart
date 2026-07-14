import 'package:flutter_riverpod/flutter_riverpod.dart' show
    AsyncNotifierProvider,
    AsyncNotifier,
    AsyncValue,
    AsyncData,
    FutureProvider,
    NotifierProvider,
    Notifier;
import '../../../shared/providers/selected_band_provider.dart';
import '../../personnel/data/models/roster.dart';
import '../../personnel/providers/roles_provider.dart';
import '../data/models/song.dart';
import '../data/songs_repository.dart';

// ── Songs state ───────────────────────────────────────────────────────────────

class SongsState {
  const SongsState({this.songs = const [], this.genres = const []});

  /// All songs of the selected band (active and inactive), sorted by title.
  final List<Song> songs;

  /// Server-defined genre options for the form's genre picker.
  final List<String> genres;

  SongsState copyWith({List<Song>? songs, List<String>? genres}) => SongsState(
        songs: songs ?? this.songs,
        genres: genres ?? this.genres,
      );
}

// ── Songs notifier ────────────────────────────────────────────────────────────

class SongsNotifier extends AsyncNotifier<SongsState> {
  @override
  Future<SongsState> build() async {
    final bandId = await ref.watch(selectedBandProvider.future);
    if (bandId == null) return const SongsState();
    return _fetch(bandId);
  }

  Future<SongsState> _fetch(int bandId) async {
    final repo = ref.read(songsRepositoryProvider);
    final payload = await repo.getSongs(bandId, includeInactive: true);
    return SongsState(songs: _sorted(payload.songs), genres: payload.genres);
  }

  List<Song> _sorted(List<Song> songs) => List<Song>.from(songs)
    ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

  int _requireBandId() {
    final bandId = ref.read(selectedBandProvider).value;
    if (bandId == null) throw StateError('No band selected.');
    return bandId;
  }

  /// Re-fetches the songs list. Used by pull-to-refresh.
  Future<void> refresh() async {
    final bandId = ref.read(selectedBandProvider).value;
    if (bandId == null) return;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _fetch(bandId));
  }

  /// Creates [draft] on the server and inserts the result locally (sorted)
  /// without a full reload.
  Future<Song> createSong(Song draft) async {
    final bandId = _requireBandId();
    final created =
        await ref.read(songsRepositoryProvider).createSong(bandId, draft);

    final current = state.value ?? const SongsState();
    state = AsyncData(
      current.copyWith(songs: _sorted([...current.songs, created])),
    );
    return created;
  }

  /// Saves [song] and replaces its local entry without a full reload.
  Future<Song> updateSong(Song song) async {
    final bandId = _requireBandId();
    final updated =
        await ref.read(songsRepositoryProvider).updateSong(bandId, song);

    final current = state.value ?? const SongsState();
    state = AsyncData(current.copyWith(
      songs: _sorted([
        for (final s in current.songs)
          if (s.id != updated.id) s,
        updated,
      ]),
    ));
    return updated;
  }

  /// Deletes on the server (owner-only, enforced server-side) then locally.
  Future<void> deleteSong(int songId) async {
    final bandId = _requireBandId();
    await ref.read(songsRepositoryProvider).deleteSong(bandId, songId);

    final current = state.value ?? const SongsState();
    state = AsyncData(current.copyWith(
      songs: current.songs.where((s) => s.id != songId).toList(),
    ));
  }
}

final songsProvider =
    AsyncNotifierProvider<SongsNotifier, SongsState>(SongsNotifier.new);

// ── Show inactive songs state ────────────────────────────────────────────────

class ShowInactiveSongsNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() {
    state = !state;
  }

  void show(bool value) {
    state = value;
  }
}

/// Whether the song list screen also shows inactive songs. The notifier
/// always fetches everything (include_inactive=1); this only filters the UI.
final showInactiveSongsProvider =
    NotifierProvider<ShowInactiveSongsNotifier, bool>(
  ShowInactiveSongsNotifier.new,
);

// ── Explicit-band songs (chart linking pickers) ───────────────────────────────

/// Songs for an explicit band. The sheet-music linked-song picker needs this
/// because a chart's band can differ from the selected band (the merged
/// library spans all of the user's bands).
final bandSongsProvider =
    FutureProvider.autoDispose.family<List<Song>, int>((ref, bandId) async {
  final payload = await ref
      .watch(songsRepositoryProvider)
      .getSongs(bandId, includeInactive: true);
  return payload.songs;
});

// ── Lead singer options ───────────────────────────────────────────────────────

/// Distinct roster members across the selected band's rosters, alphabetised —
/// options for the song form's lead singer picker. The rosters index may omit
/// members, so each roster's detail is fetched (bands typically have 1–2).
final leadSingerOptionsProvider =
    FutureProvider.autoDispose<List<RosterMember>>((ref) async {
  final bandId = await ref.watch(selectedBandProvider.future);
  if (bandId == null) return const [];

  final repo = ref.watch(personnelRepositoryProvider);
  final rosters = await repo.getRosters(bandId);
  final detailed = await Future.wait(
    rosters.map((r) => r.members.isNotEmpty
        ? Future.value(r)
        : repo.getRoster(bandId, r.id)),
  );

  final seen = <int>{};
  final members = <RosterMember>[];
  for (final roster in detailed) {
    for (final member in roster.members) {
      if (seen.add(member.id)) members.add(member);
    }
  }
  members.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return members;
});
