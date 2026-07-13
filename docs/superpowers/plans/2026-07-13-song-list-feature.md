# Song List Feature (Flutter) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Full song-list management (browse / search / add / edit / owner-only delete) in the Flutter app, a segmented Library tab ("Song list | Sheet music"), songs↔charts linking on the chart screens, and a "Sheet music" relabel of all user-facing "Chart(s)" copy — the mobile half of `TTS/docs/superpowers/specs/2026-07-13-mobile-song-list-design.md`.

**Architecture:** New vertical slice `lib/features/songs/` modeled exactly on `lib/features/library/` (hand-written model → Dio repository → Riverpod `AsyncNotifier` → Cupertino screens). The Library tab becomes a thin `LibraryTabScreen` wrapper with a `CupertinoSlidingSegmentedControl` switching between the new `SongListScreen` and the existing `LibraryScreen` (unchanged). Chart linking reuses the songs repository via a `bandSongsProvider` family and the new backend `PATCH /api/mobile/bands/{band}/charts/{chart}` endpoint.

**Tech Stack:** Flutter (Cupertino widgets), Riverpod v2 (`AsyncNotifier`), Dio, GoRouter, flutter_test (`ProviderContainer` + fakes, widget tests with a stub GoRouter).

## Global Constraints

- **Repo:** `/home/eddie/github/tts_bandmate` (NOT the Laravel repo). All paths below are relative to it.
- **Commands run directly on the host** (this repo has no docker wrapper — per its `CLAUDE.md`): `flutter test test/path/to_test.dart`, `flutter analyze`, `flutter pub get`.
- **Branch:** create `feat/song-list` off `main` before Task 1. PRs for this repo target `main` (repo default; the `staging` rule is for the Laravel `TTS` repo only).
- **Models are hand-written** `fromJson()` factories with safe null coalescing (`?? ''`, `?? 0`, `(json['x'] as num?)?.toInt()`). **No freezed/json_serializable codegen** even though those packages sit in dev_dependencies.
- **Cupertino everywhere** — `CupertinoPageScaffold`, `CupertinoNavigationBar`, `CupertinoColors.*.resolveFrom(context)`, and the theme helpers `context.primaryText` / `context.secondaryText` / `context.tertiaryText` from `package:tts_bandmate/core/theme/context_colors.dart`.
- **Router ordering rule** (quoted from `lib/core/config/router.dart`): "Literal-segment routes before parameterised ones to avoid ambiguity" — `/songs/new` MUST precede `/songs/:songId`.
- **Riverpod layering:** `data/` (models + repository, repository takes `Dio` via constructor and is exposed by a plain `Provider`), `providers/` (notifiers), `screens/`, `widgets/`.
- **Tests** mirror `lib/` under `test/`; repository tests fake Dio with a private `_FakeAdapter implements HttpClientAdapter` (see `test/features/setlist_editor/setlist_editor_repository_test.dart`); provider tests use `ProviderContainer` with `overrideWithValue`/`overrideWith` fakes; widget tests build a `ProviderScope` harness with a stub `GoRouter`.
- **Backend contract** (from `TTS/docs/superpowers/plans/2026-07-13-song-list-mobile-api-and-web.md` — copy exactly, never guess):
  - `GET /api/mobile/bands/{band}/songs` (add `?include_inactive=1` for all songs) → `{"songs": [{id, band_id, title, artist, song_key, genre, bpm, notes, rating, energy, active, lead_singer: {id, display_name}|null, transition_song: {id, title, artist}|null, charts: [{id, title}]}], "genres": ["Blues", ...]}`. `bpm` is always an int (server sends `?? 0`); `rating`/`energy` are nullable ints.
  - `POST /api/mobile/bands/{band}/songs` → `201 {"song": {...}}` (same shape).
  - `PATCH /api/mobile/bands/{band}/songs/{song}` → `200 {"song": {...}}`.
  - `DELETE /api/mobile/bands/{band}/songs/{song}` → `200 {"message": "Song deleted."}` (owner-only; 403 otherwise).
  - `GET /api/mobile/songs/lookup?title=…&artist=…` → service passthrough JSON, e.g. `{"bpm": 100, "song_key": "E♭m"}`.
  - Write validation (server-side): `title` required max:255; `bpm` 1–999 (so **send `null`, never `0`**); `rating`/`energy` 1–10; `lead_singer_id` must be a roster member id; `transition_song_id` a same-band song id.
  - `POST /api/mobile/bands/{band}/charts` accepts optional `song_id`; **new** `PATCH /api/mobile/bands/{band}/charts/{chart}` accepts partial `title/composer/description/price/is_public/song_id`; chart payloads now include `"song": {id, title, artist}|null`.
  - A 403 with message `Insufficient token permissions.` is auto-recovered by the existing stale-token single-retry refresh in `api_client.dart` — no app-side handling needed.
- **Permission signals available to the app (investigated):** the app decodes **no token abilities** and has **no per-resource `can_write` flag** outside the setlist payload. The existing library (charts) feature shows its add/create/delete affordances **unconditionally** and lets the server 403; the only local signal is `BandSummary.isOwner` (`is_owner` from the auth payload), used e.g. by `OperationsScreen` to gate the Personnel row. **This plan follows the library pattern:** add/edit affordances always visible (server enforces `write:songs`, errors surface in the form's error banner); the **delete** affordance is gated locally by the selected band's `isOwner` (server enforces owner-only too). *This deviates from the spec line "Add/edit affordances hidden without `write:songs`" because no such signal exists in the app or in the songs API payload — flagged for the product owner; adding `can_write` to the songs index payload later would let us tighten this.*
- **Copy rules:** segment labels are exactly `Song list` and `Sheet music`. Relabeled chart copy uses "Sheet Music" in Title Case contexts (nav bars, dialog titles) and "sheet music" mid-sentence. Identifiers, route paths, file names, and the `charts` permission key are NEVER renamed.
- Commit after every green task; commit messages end with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

---

### Task 0: Branch

- [ ] **Step 1: Create the working branch**

```bash
cd /home/eddie/github/tts_bandmate
git checkout main && git pull
git checkout -b feat/song-list
```

---

### Task 1: `Song` model

**Files:**
- Create: `lib/features/songs/data/models/song.dart`
- Test: `test/features/songs/data/models/song_test.dart`

**Interfaces:**
- Produces (everything later tasks rely on — exact names):
  - `class Song` — fields `int id`, `int bandId`, `String title`, `String artist`, `String songKey`, `String genre`, `int bpm` (0 = unset), `String notes`, `int? rating`, `int? energy`, `bool active`, `SongLeadSinger? leadSinger`, `SongRef? transitionSong`, `List<SongChartSummary> charts`; `factory Song.fromJson(Map<String, dynamic>)`, `Map<String, dynamic> toJson()`, `Map<String, dynamic> toUpdateJson()`.
  - `class SongLeadSinger { int id; String displayName; }`
  - `class SongRef { int id; String title; String artist; }`
  - `class SongChartSummary { int id; String title; }`

- [ ] **Step 1: Write the failing test**

Create `test/features/songs/data/models/song_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/songs/data/models/song.dart';

void main() {
  group('Song.fromJson', () {
    test('parses a full payload', () {
      final song = Song.fromJson({
        'id': 5,
        'band_id': 2,
        'title': 'Uptown Funk',
        'artist': 'Bruno Mars',
        'song_key': 'Dm',
        'genre': 'Funk',
        'bpm': 115,
        'notes': 'Horns!',
        'rating': 8,
        'energy': 9,
        'active': true,
        'lead_singer': {'id': 3, 'display_name': 'Alex'},
        'transition_song': {'id': 9, 'title': 'Treasure', 'artist': 'Bruno Mars'},
        'charts': [
          {'id': 11, 'title': 'Uptown Funk - Horns'},
        ],
      });

      expect(song.id, 5);
      expect(song.bandId, 2);
      expect(song.title, 'Uptown Funk');
      expect(song.artist, 'Bruno Mars');
      expect(song.songKey, 'Dm');
      expect(song.genre, 'Funk');
      expect(song.bpm, 115);
      expect(song.notes, 'Horns!');
      expect(song.rating, 8);
      expect(song.energy, 9);
      expect(song.active, true);
      expect(song.leadSinger!.id, 3);
      expect(song.leadSinger!.displayName, 'Alex');
      expect(song.transitionSong!.id, 9);
      expect(song.transitionSong!.title, 'Treasure');
      expect(song.charts, hasLength(1));
      expect(song.charts.first.id, 11);
      expect(song.charts.first.title, 'Uptown Funk - Horns');
    });

    test('null-coalesces missing optional fields', () {
      final song = Song.fromJson({
        'id': 1,
        'band_id': 2,
        'title': 'Bare',
        'lead_singer': null,
        'transition_song': null,
      });

      expect(song.artist, '');
      expect(song.songKey, '');
      expect(song.genre, '');
      expect(song.bpm, 0);
      expect(song.notes, '');
      expect(song.rating, isNull);
      expect(song.energy, isNull);
      expect(song.active, true);
      expect(song.leadSinger, isNull);
      expect(song.transitionSong, isNull);
      expect(song.charts, isEmpty);
    });
  });

  group('Song.toUpdateJson', () {
    test('maps writable fields and nested ids', () {
      const song = Song(
        id: 5,
        bandId: 2,
        title: 'Uptown Funk',
        artist: 'Bruno Mars',
        songKey: 'Dm',
        genre: 'Funk',
        bpm: 115,
        notes: 'Horns!',
        rating: 8,
        energy: 9,
        active: false,
        leadSinger: SongLeadSinger(id: 3, displayName: 'Alex'),
        transitionSong: SongRef(id: 9, title: 'Treasure', artist: 'Bruno Mars'),
      );

      expect(song.toUpdateJson(), {
        'title': 'Uptown Funk',
        'artist': 'Bruno Mars',
        'song_key': 'Dm',
        'genre': 'Funk',
        'bpm': 115,
        'notes': 'Horns!',
        'rating': 8,
        'energy': 9,
        'lead_singer_id': 3,
        'transition_song_id': 9,
        'active': false,
      });
    });

    test('sends null for empty strings and zero bpm (server rules: bpm min 1)', () {
      const song = Song(id: 0, bandId: 2, title: 'Bare');

      final json = song.toUpdateJson();
      expect(json['artist'], isNull);
      expect(json['song_key'], isNull);
      expect(json['genre'], isNull);
      expect(json['bpm'], isNull);
      expect(json['notes'], isNull);
      expect(json['rating'], isNull);
      expect(json['energy'], isNull);
      expect(json['lead_singer_id'], isNull);
      expect(json['transition_song_id'], isNull);
      expect(json['active'], true);
    });
  });

  test('toJson round-trips through fromJson', () {
    const song = Song(
      id: 5,
      bandId: 2,
      title: 'Uptown Funk',
      artist: 'Bruno Mars',
      rating: 8,
      leadSinger: SongLeadSinger(id: 3, displayName: 'Alex'),
      charts: [SongChartSummary(id: 11, title: 'Horns')],
    );

    final restored = Song.fromJson(song.toJson());
    expect(restored.id, 5);
    expect(restored.title, 'Uptown Funk');
    expect(restored.rating, 8);
    expect(restored.leadSinger!.displayName, 'Alex');
    expect(restored.charts.first.title, 'Horns');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/songs/data/models/song_test.dart`
Expected: FAIL — compile error, `package:tts_bandmate/features/songs/data/models/song.dart` does not exist.

- [ ] **Step 3: Write the model**

Create `lib/features/songs/data/models/song.dart`:

```dart
/// Lead singer block on a [Song] (`"lead_singer": {id, display_name}|null`).
class SongLeadSinger {
  const SongLeadSinger({required this.id, required this.displayName});

  final int id;
  final String displayName;

  factory SongLeadSinger.fromJson(Map<String, dynamic> json) => SongLeadSinger(
        id: (json['id'] as num).toInt(),
        displayName: json['display_name'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {'id': id, 'display_name': displayName};
}

/// Minimal reference to another song — the transition-song block
/// (`"transition_song": {id, title, artist}|null`).
class SongRef {
  const SongRef({required this.id, required this.title, this.artist = ''});

  final int id;
  final String title;
  final String artist;

  factory SongRef.fromJson(Map<String, dynamic> json) => SongRef(
        id: (json['id'] as num).toInt(),
        title: json['title'] as String? ?? '',
        artist: json['artist'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'artist': artist};
}

/// Linked sheet-music summary carried on a [Song] (`"charts": [{id, title}]`).
class SongChartSummary {
  const SongChartSummary({required this.id, required this.title});

  final int id;
  final String title;

  factory SongChartSummary.fromJson(Map<String, dynamic> json) =>
      SongChartSummary(
        id: (json['id'] as num).toInt(),
        title: json['title'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {'id': id, 'title': title};
}

/// A band repertoire song, as returned by
/// GET /api/mobile/bands/{band}/songs.
class Song {
  const Song({
    required this.id,
    required this.bandId,
    required this.title,
    this.artist = '',
    this.songKey = '',
    this.genre = '',
    this.bpm = 0,
    this.notes = '',
    this.rating,
    this.energy,
    this.active = true,
    this.leadSinger,
    this.transitionSong,
    this.charts = const [],
  });

  final int id;
  final int bandId;
  final String title;
  final String artist;
  final String songKey;
  final String genre;

  /// Beats per minute; 0 means unset (the API sends `bpm ?? 0`).
  final int bpm;
  final String notes;

  /// 1–10, null when unrated.
  final int? rating;

  /// 1–10, null when unset.
  final int? energy;
  final bool active;
  final SongLeadSinger? leadSinger;
  final SongRef? transitionSong;
  final List<SongChartSummary> charts;

  factory Song.fromJson(Map<String, dynamic> json) => Song(
        id: (json['id'] as num).toInt(),
        bandId: (json['band_id'] as num).toInt(),
        title: json['title'] as String? ?? '',
        artist: json['artist'] as String? ?? '',
        songKey: json['song_key'] as String? ?? '',
        genre: json['genre'] as String? ?? '',
        bpm: (json['bpm'] as num?)?.toInt() ?? 0,
        notes: json['notes'] as String? ?? '',
        rating: (json['rating'] as num?)?.toInt(),
        energy: (json['energy'] as num?)?.toInt(),
        active: json['active'] as bool? ?? true,
        leadSinger: json['lead_singer'] is Map<String, dynamic>
            ? SongLeadSinger.fromJson(json['lead_singer'] as Map<String, dynamic>)
            : null,
        transitionSong: json['transition_song'] is Map<String, dynamic>
            ? SongRef.fromJson(json['transition_song'] as Map<String, dynamic>)
            : null,
        charts: (json['charts'] as List<dynamic>?)
                ?.map((c) => SongChartSummary.fromJson(c as Map<String, dynamic>))
                .toList() ??
            const [],
      );

  /// Full round-trip serialisation (state persistence, tests).
  Map<String, dynamic> toJson() => {
        'id': id,
        'band_id': bandId,
        'title': title,
        'artist': artist,
        'song_key': songKey,
        'genre': genre,
        'bpm': bpm,
        'notes': notes,
        'rating': rating,
        'energy': energy,
        'active': active,
        'lead_singer': leadSinger?.toJson(),
        'transition_song': transitionSong?.toJson(),
        'charts': charts.map((c) => c.toJson()).toList(),
      };

  /// Writable-field payload for POST / PATCH. The server derives the band
  /// from the route, and its rules reject bpm 0 (min:1) — empty values are
  /// sent as null to satisfy the `nullable|…` validation rules.
  Map<String, dynamic> toUpdateJson() => {
        'title': title,
        'artist': artist.isEmpty ? null : artist,
        'song_key': songKey.isEmpty ? null : songKey,
        'genre': genre.isEmpty ? null : genre,
        'bpm': bpm > 0 ? bpm : null,
        'notes': notes.isEmpty ? null : notes,
        'rating': rating,
        'energy': energy,
        'lead_singer_id': leadSinger?.id,
        'transition_song_id': transitionSong?.id,
        'active': active,
      };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/songs/data/models/song_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/songs/data/models/song.dart test/features/songs/data/models/song_test.dart
git commit -m "feat(songs): unified Song model with fromJson/toJson/toUpdateJson

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: API endpoints + `SongsRepository`

**Files:**
- Modify: `lib/core/network/api_endpoints.dart` (after line 99, `mobileBandSongs`)
- Create: `lib/features/songs/data/songs_repository.dart`
- Test: `test/features/songs/data/songs_repository_test.dart`

**Interfaces:**
- Consumes: `Song` (Task 1); existing `ApiEndpoints.mobileBandSongs(int bandId)`; `apiClientProvider` via the `core_providers.dart` barrel.
- Produces:
  - `ApiEndpoints.mobileBandSong(int bandId, int songId)` → `/api/mobile/bands/$bandId/songs/$songId`
  - `ApiEndpoints.mobileSongsLookup` → `/api/mobile/songs/lookup`
  - `class SongsRepository { SongsRepository(Dio dio); Future<({List<Song> songs, List<String> genres})> getSongs(int bandId, {bool includeInactive = false}); Future<Song> createSong(int bandId, Song song); Future<Song> updateSong(int bandId, Song song); Future<void> deleteSong(int bandId, int songId); Future<Map<String, dynamic>> lookupBpm({required String title, String? artist}); }`
  - `final songsRepositoryProvider = Provider<SongsRepository>` — Tasks 3–7 override/consume this.

- [ ] **Step 1: Write the failing test**

Create `test/features/songs/data/songs_repository_test.dart` (fake-adapter idiom copied from `test/features/setlist_editor/setlist_editor_repository_test.dart`):

```dart
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/songs/data/models/song.dart';
import 'package:tts_bandmate/features/songs/data/songs_repository.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.responder);

  final Future<ResponseBody> Function(RequestOptions) responder;

  @override
  Future<ResponseBody> fetch(RequestOptions options, _, __) => responder(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int status, Object body) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        'content-type': ['application/json'],
      },
    );

Map<String, dynamic> _songJson(int id, String title, {bool active = true}) => {
      'id': id,
      'band_id': 1,
      'title': title,
      'artist': '',
      'song_key': '',
      'genre': '',
      'bpm': 0,
      'notes': '',
      'rating': null,
      'energy': null,
      'active': active,
      'lead_singer': null,
      'transition_song': null,
      'charts': <Map<String, dynamic>>[],
    };

void main() {
  late Dio dio;

  setUp(() {
    dio = Dio();
  });

  test('getSongs hits the band songs path and parses songs + genres', () async {
    dio.httpClientAdapter = _FakeAdapter((req) async {
      expect(req.path, '/api/mobile/bands/1/songs');
      expect(req.method, 'GET');
      expect(req.queryParameters, isEmpty);
      return _json(200, {
        'songs': [_songJson(10, 'September')],
        'genres': ['Funk', 'Soul'],
      });
    });

    final repo = SongsRepository(dio);
    final result = await repo.getSongs(1);

    expect(result.songs, hasLength(1));
    expect(result.songs.first.title, 'September');
    expect(result.genres, ['Funk', 'Soul']);
  });

  test('getSongs passes include_inactive=1 when requested', () async {
    dio.httpClientAdapter = _FakeAdapter((req) async {
      expect(req.queryParameters, {'include_inactive': 1});
      return _json(200, {'songs': <Map<String, dynamic>>[], 'genres': <String>[]});
    });

    final repo = SongsRepository(dio);
    await repo.getSongs(1, includeInactive: true);
  });

  test('createSong POSTs toUpdateJson and parses the song envelope', () async {
    Map<String, dynamic>? capturedBody;
    dio.httpClientAdapter = _FakeAdapter((req) async {
      capturedBody = req.data as Map<String, dynamic>;
      expect(req.path, '/api/mobile/bands/1/songs');
      expect(req.method, 'POST');
      return _json(201, {'song': _songJson(99, 'New Song')});
    });

    final repo = SongsRepository(dio);
    final created = await repo.createSong(
      1,
      const Song(id: 0, bandId: 1, title: 'New Song', bpm: 120),
    );

    expect(capturedBody!['title'], 'New Song');
    expect(capturedBody!['bpm'], 120);
    expect(capturedBody!['artist'], isNull);
    expect(created.id, 99);
  });

  test('updateSong PATCHes the song path', () async {
    dio.httpClientAdapter = _FakeAdapter((req) async {
      expect(req.path, '/api/mobile/bands/1/songs/7');
      expect(req.method, 'PATCH');
      expect((req.data as Map<String, dynamic>)['title'], 'Renamed');
      return _json(200, {'song': _songJson(7, 'Renamed')});
    });

    final repo = SongsRepository(dio);
    final updated =
        await repo.updateSong(1, const Song(id: 7, bandId: 1, title: 'Renamed'));

    expect(updated.title, 'Renamed');
  });

  test('deleteSong DELETEs the song path', () async {
    dio.httpClientAdapter = _FakeAdapter((req) async {
      expect(req.path, '/api/mobile/bands/1/songs/7');
      expect(req.method, 'DELETE');
      return _json(200, {'message': 'Song deleted.'});
    });

    final repo = SongsRepository(dio);
    await repo.deleteSong(1, 7);
  });

  test('lookupBpm GETs /api/mobile/songs/lookup with title and artist', () async {
    dio.httpClientAdapter = _FakeAdapter((req) async {
      expect(req.path, '/api/mobile/songs/lookup');
      expect(req.method, 'GET');
      expect(req.queryParameters,
          {'title': 'Superstition', 'artist': 'Stevie Wonder'});
      return _json(200, {'bpm': 100, 'song_key': 'E♭m'});
    });

    final repo = SongsRepository(dio);
    final result =
        await repo.lookupBpm(title: 'Superstition', artist: 'Stevie Wonder');

    expect(result['bpm'], 100);
    expect(result['song_key'], 'E♭m');
  });

  test('lookupBpm omits an empty artist', () async {
    dio.httpClientAdapter = _FakeAdapter((req) async {
      expect(req.queryParameters, {'title': 'Superstition'});
      return _json(200, {'bpm': 100});
    });

    final repo = SongsRepository(dio);
    await repo.lookupBpm(title: 'Superstition', artist: '');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/songs/data/songs_repository_test.dart`
Expected: FAIL — compile error, `songs_repository.dart` does not exist.

- [ ] **Step 3: Add the endpoints**

In `lib/core/network/api_endpoints.dart`, the songs/charts block currently reads (line 99):

```dart
  static String mobileBandSongs(int bandId) => '/api/mobile/bands/$bandId/songs';
```

Insert directly below it:

```dart
  static String mobileBandSong(int bandId, int songId) =>
      '/api/mobile/bands/$bandId/songs/$songId';

  /// BPM lookup passthrough (band-independent, like the web /songs/lookup).
  static const String mobileSongsLookup = '/api/mobile/songs/lookup';
```

- [ ] **Step 4: Write the repository**

Create `lib/features/songs/data/songs_repository.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tts_bandmate/core/providers/core_providers.dart';
import 'models/song.dart';

class SongsRepository {
  SongsRepository(this._dio);

  final Dio _dio;

  /// Fetches the band's songs plus the server-defined genre list.
  ///
  /// The API defaults to active-only (search + setlist picker behaviour);
  /// pass [includeInactive] for the management screen.
  Future<({List<Song> songs, List<String> genres})> getSongs(
    int bandId, {
    bool includeInactive = false,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileBandSongs(bandId),
      queryParameters: {if (includeInactive) 'include_inactive': 1},
    );

    final data = response.data!;
    final rawSongs = data['songs'] as List<dynamic>;
    final rawGenres = data['genres'] as List<dynamic>? ?? const [];
    return (
      songs: rawSongs.cast<Map<String, dynamic>>().map(Song.fromJson).toList(),
      genres: rawGenres.cast<String>(),
    );
  }

  /// Creates a song for [bandId]. [song.id] is ignored (use 0 for drafts).
  Future<Song> createSong(int bandId, Song song) async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.mobileBandSongs(bandId),
      data: song.toUpdateJson(),
    );
    return Song.fromJson(response.data!['song'] as Map<String, dynamic>);
  }

  /// Updates an existing song (full writable-field PATCH).
  Future<Song> updateSong(int bandId, Song song) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      ApiEndpoints.mobileBandSong(bandId, song.id),
      data: song.toUpdateJson(),
    );
    return Song.fromJson(response.data!['song'] as Map<String, dynamic>);
  }

  /// Deletes a song. Server enforces owner-only (403 otherwise).
  Future<void> deleteSong(int bandId, int songId) async {
    await _dio.delete(ApiEndpoints.mobileBandSong(bandId, songId));
  }

  /// BPM lookup passthrough, e.g. `{"bpm": 100, "song_key": "E♭m"}`.
  /// Keys may be absent when the external service finds nothing.
  Future<Map<String, dynamic>> lookupBpm({
    required String title,
    String? artist,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileSongsLookup,
      queryParameters: {
        'title': title,
        if (artist != null && artist.isNotEmpty) 'artist': artist,
      },
    );
    return response.data ?? const {};
  }
}

final songsRepositoryProvider = Provider<SongsRepository>((ref) {
  return SongsRepository(ref.watch(apiClientProvider).dio);
});
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/features/songs/data/songs_repository_test.dart`
Expected: PASS (7 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/core/network/api_endpoints.dart lib/features/songs/data/songs_repository.dart test/features/songs/data/songs_repository_test.dart
git commit -m "feat(songs): songs repository and mobile API endpoints

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Songs providers

**Files:**
- Create: `lib/features/songs/providers/songs_provider.dart`
- Test: `test/features/songs/providers/songs_provider_test.dart`

**Interfaces:**
- Consumes: `songsRepositoryProvider` (Task 2), `selectedBandProvider` (`lib/shared/providers/selected_band_provider.dart`), `personnelRepositoryProvider` (`lib/features/personnel/providers/roles_provider.dart` — where it is declared), `RosterMember` (`lib/features/personnel/data/models/roster.dart`).
- Produces:
  - `class SongsState { List<Song> songs; List<String> genres; SongsState copyWith(...); }`
  - `class SongsNotifier extends AsyncNotifier<SongsState>` with `refresh()`, `Future<Song> createSong(Song draft)`, `Future<Song> updateSong(Song song)`, `Future<void> deleteSong(int songId)`
  - `final songsProvider = AsyncNotifierProvider<SongsNotifier, SongsState>`
  - `final showInactiveSongsProvider = StateProvider<bool>` (default `false`)
  - `final bandSongsProvider = FutureProvider.autoDispose.family<List<Song>, int>` (explicit band — chart linking pickers)
  - `final leadSingerOptionsProvider = FutureProvider.autoDispose<List<RosterMember>>` (deduped roster members of the selected band)

- [ ] **Step 1: Write the failing test**

Create `test/features/songs/providers/songs_provider_test.dart`:

```dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/songs/providers/songs_provider_test.dart`
Expected: FAIL — compile error, `songs_provider.dart` does not exist.

- [ ] **Step 3: Write the providers**

Create `lib/features/songs/providers/songs_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

/// Whether the song list screen also shows inactive songs. The notifier
/// always fetches everything (include_inactive=1); this only filters the UI.
final showInactiveSongsProvider = StateProvider<bool>((_) => false);

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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/songs/providers/songs_provider_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/songs/providers/songs_provider.dart test/features/songs/providers/songs_provider_test.dart
git commit -m "feat(songs): songs AsyncNotifier, inactive filter, band-scoped and lead-singer providers

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Song list screen + segmented Library tab

**Files:**
- Create: `lib/features/songs/screens/song_list_screen.dart`
- Create: `lib/features/library/screens/library_tab_screen.dart`
- Modify: `lib/core/config/router.dart` (swap `/library` builder; add `/songs`)
- Test: `test/features/songs/screens/song_list_screen_test.dart`
- Test: `test/features/library/screens/library_tab_screen_test.dart`

**Interfaces:**
- Consumes: `songsProvider`, `showInactiveSongsProvider` (Task 3), `authProvider` / `AuthAuthenticated` (`lib/features/auth/providers/auth_provider.dart`), `selectedBandProvider`, `ErrorView` / `EmptyStateView` (`lib/shared/widgets/`), `LibraryScreen` (unchanged).
- Produces: `class SongListScreen extends ConsumerStatefulWidget` (no constructor params); `class LibraryTabScreen extends StatefulWidget`; routes `/library` → `LibraryTabScreen`, `/songs` → `SongListScreen`. The list pushes `/songs/new` (Task 5) and `/songs/{id}` (Task 6) — those routes land with their screens; until then tapping shows the router's "Page not found" error page, which is acceptable mid-plan.

- [ ] **Step 1: Write the failing widget tests**

Create `test/features/songs/screens/song_list_screen_test.dart`:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tts_bandmate/features/auth/data/models/auth_user.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/auth/providers/auth_provider.dart';
import 'package:tts_bandmate/features/songs/data/models/song.dart';
import 'package:tts_bandmate/features/songs/data/songs_repository.dart';
import 'package:tts_bandmate/features/songs/providers/songs_provider.dart';
import 'package:tts_bandmate/features/songs/screens/song_list_screen.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';

const _user = AuthUser(id: 1, name: 'Eddie', email: 'e@e.com');

class _StubAuth extends AuthNotifier {
  _StubAuth(this._bands);
  final List<BandSummary> _bands;
  @override
  Future<AuthState> build() async => AuthAuthenticated(user: _user, bands: _bands);
}

class _StubBand extends SelectedBandNotifier {
  @override
  Future<int?> build() async => 1;
}

class _FakeRepo implements SongsRepository {
  _FakeRepo(this._songs);
  final List<Song> _songs;
  int? lastDeletedSongId;

  @override
  Future<({List<Song> songs, List<String> genres})> getSongs(
    int bandId, {
    bool includeInactive = false,
  }) async =>
      (songs: _songs, genres: const <String>[]);

  @override
  Future<void> deleteSong(int bandId, int songId) async {
    lastDeletedSongId = songId;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Widget _harness(_FakeRepo repo, {bool owner = true}) {
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => const SongListScreen()),
  ]);
  return ProviderScope(
    overrides: [
      authProvider.overrideWith(
          () => _StubAuth([BandSummary(id: 1, name: 'Band', isOwner: owner)])),
      selectedBandProvider.overrideWith(_StubBand.new),
      songsRepositoryProvider.overrideWithValue(repo),
    ],
    child: CupertinoApp.router(routerConfig: router),
  );
}

const _songs = [
  Song(id: 1, bandId: 1, title: 'Caravan', artist: 'Ellington'),
  Song(id: 2, bandId: 1, title: 'Autumn Leaves'),
  Song(id: 3, bandId: 1, title: 'Retired Tune', active: false),
];

void main() {
  testWidgets('renders active songs alphabetised and hides inactive by default',
      (tester) async {
    await tester.pumpWidget(_harness(_FakeRepo(_songs)));
    await tester.pumpAndSettle();

    expect(find.text('Autumn Leaves'), findsOneWidget);
    expect(find.text('Caravan'), findsOneWidget);
    expect(find.text('Retired Tune'), findsNothing);
  });

  testWidgets('inactive toggle reveals inactive songs', (tester) async {
    await tester.pumpWidget(_harness(_FakeRepo(_songs)));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Show inactive songs'));
    await tester.pumpAndSettle();

    expect(find.text('Retired Tune'), findsOneWidget);
    expect(find.text('Inactive'), findsOneWidget);
  });

  testWidgets('search filters by title and artist', (tester) async {
    await tester.pumpWidget(_harness(_FakeRepo(_songs)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(CupertinoSearchTextField), 'elling');
    await tester.pumpAndSettle();

    expect(find.text('Caravan'), findsOneWidget);
    expect(find.text('Autumn Leaves'), findsNothing);
  });

  testWidgets('owner long-press shows the delete confirmation and deletes',
      (tester) async {
    final repo = _FakeRepo(_songs);
    await tester.pumpWidget(_harness(repo));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Caravan'));
    await tester.pumpAndSettle();
    expect(find.text('Delete Song'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(repo.lastDeletedSongId, 1);
    expect(find.text('Caravan'), findsNothing);
  });

  testWidgets('non-owner long-press does nothing', (tester) async {
    await tester.pumpWidget(_harness(_FakeRepo(_songs), owner: false));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Caravan'));
    await tester.pumpAndSettle();

    expect(find.text('Delete Song'), findsNothing);
  });

  testWidgets('empty band shows the empty state', (tester) async {
    await tester.pumpWidget(_harness(_FakeRepo(const [])));
    await tester.pumpAndSettle();

    expect(find.text('No songs yet'), findsOneWidget);
  });
}
```

Create `test/features/library/screens/library_tab_screen_test.dart`:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tts_bandmate/features/auth/data/models/auth_user.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/auth/providers/auth_provider.dart';
import 'package:tts_bandmate/features/library/data/library_repository.dart';
import 'package:tts_bandmate/features/library/data/models/chart.dart';
import 'package:tts_bandmate/features/library/screens/library_tab_screen.dart';
import 'package:tts_bandmate/features/songs/data/models/song.dart';
import 'package:tts_bandmate/features/songs/data/songs_repository.dart';
import 'package:tts_bandmate/features/songs/providers/songs_provider.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';

const _user = AuthUser(id: 1, name: 'Eddie', email: 'e@e.com');
const _band = BandSummary(id: 1, name: 'Band A', isOwner: true);

class _StubAuth extends AuthNotifier {
  @override
  Future<AuthState> build() async =>
      AuthAuthenticated(user: _user, bands: const [_band]);
}

class _StubBand extends SelectedBandNotifier {
  @override
  Future<int?> build() async => 1;
}

class _FakeSongsRepo implements SongsRepository {
  @override
  Future<({List<Song> songs, List<String> genres})> getSongs(
    int bandId, {
    bool includeInactive = false,
  }) async =>
      (
        songs: const [Song(id: 1, bandId: 1, title: 'My Song')],
        genres: const <String>[],
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakeLibraryRepo implements LibraryRepository {
  @override
  Future<List<Chart>> getAllCharts() async => const [
        Chart(
          id: 1,
          bandId: 1,
          title: 'My Chart',
          composer: '',
          description: '',
          price: 0,
          isPublic: false,
          uploadsCount: 0,
          uploads: [],
          band: ChartBand(id: 1, name: 'Band A', isPersonal: false),
        ),
      ];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Widget _harness() {
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => const LibraryTabScreen()),
  ]);
  return ProviderScope(
    overrides: [
      authProvider.overrideWith(_StubAuth.new),
      selectedBandProvider.overrideWith(_StubBand.new),
      songsRepositoryProvider.overrideWithValue(_FakeSongsRepo()),
      libraryRepositoryProvider.overrideWithValue(_FakeLibraryRepo()),
    ],
    child: CupertinoApp.router(routerConfig: router),
  );
}

void main() {
  testWidgets('shows both segments and defaults to Song list', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    // 'Song list' appears in both the segment and the embedded screen's nav
    // bar (which can render large + collapsed title Texts) — use findsWidgets.
    expect(find.text('Song list'), findsWidgets);
    expect(find.text('Sheet music'), findsOneWidget);
    expect(find.text('My Song'), findsOneWidget);
    expect(find.text('My Chart'), findsNothing);
  });

  testWidgets('switching to Sheet music renders the library screen',
      (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sheet music'));
    await tester.pumpAndSettle();

    expect(find.text('My Chart'), findsOneWidget);
    expect(find.text('My Song'), findsNothing);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/songs/screens/song_list_screen_test.dart test/features/library/screens/library_tab_screen_test.dart`
Expected: FAIL — compile errors, the two screens do not exist.

- [ ] **Step 3: Write the song list screen**

Create `lib/features/songs/screens/song_list_screen.dart`:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';
import 'package:tts_bandmate/shared/widgets/empty_state_view.dart';
import 'package:tts_bandmate/shared/widgets/error_view.dart';

import '../../auth/providers/auth_provider.dart';
import '../../../shared/providers/selected_band_provider.dart';
import '../data/models/song.dart';
import '../providers/songs_provider.dart';

/// The band's song list (repertoire) — browse, search, add, edit, and
/// (owner-only) delete. Rendered inside the segmented Library tab and pushed
/// standalone from the Operations screen ('/songs').
class SongListScreen extends ConsumerStatefulWidget {
  const SongListScreen({super.key});

  @override
  ConsumerState<SongListScreen> createState() => _SongListScreenState();
}

class _SongListScreenState extends ConsumerState<SongListScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() => ref.read(songsProvider.notifier).refresh();

  bool get _isOwner {
    final auth = ref.read(authProvider).value;
    final bandId = ref.read(selectedBandProvider).value;
    if (auth is! AuthAuthenticated || bandId == null) return false;
    return auth.bands.where((b) => b.id == bandId).firstOrNull?.isOwner ??
        false;
  }

  Future<void> _openCreateAndMaybeOpenDetail() async {
    final created = await context.push<Song>('/songs/new');
    if (!mounted || created == null) return;
    context.push('/songs/${created.id}');
  }

  Future<void> _confirmDeleteSong(Song song) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Delete Song'),
        content: Text(
            'Are you sure you want to delete "${song.title}"? Linked sheet music is kept. This cannot be undone.'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await ref.read(songsProvider.notifier).deleteSong(song.id);
    } catch (e) {
      if (mounted) {
        showCupertinoDialog<void>(
          context: context,
          builder: (ctx) => CupertinoAlertDialog(
            title: const Text('Delete Failed'),
            content: Text(ErrorView.friendlyMessage(e)),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  List<Song> _visibleSongs(SongsState state, bool showInactive) {
    var songs = state.songs.where((s) => showInactive || s.active);
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      songs = songs.where((s) =>
          s.title.toLowerCase().contains(q) ||
          s.artist.toLowerCase().contains(q));
    }
    return songs.toList();
  }

  @override
  Widget build(BuildContext context) {
    final songsAsync = ref.watch(songsProvider);
    final showInactive = ref.watch(showInactiveSongsProvider);

    return CupertinoPageScaffold(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth =
              constraints.maxWidth > 700 ? 700.0 : constraints.maxWidth;

          return Center(
            child: SizedBox(
              width: maxWidth,
              child: Column(
                children: [
                  Expanded(
                    child: songsAsync.when(
                      loading: () =>
                          const Center(child: CupertinoActivityIndicator()),
                      error: (e, _) => CustomScrollView(
                        slivers: [
                          _buildNavBar(context, showInactive),
                          SliverFillRemaining(
                            child: ErrorView(
                              message: ErrorView.friendlyMessage(e),
                              onRetry: _refresh,
                            ),
                          ),
                        ],
                      ),
                      data: (state) {
                        final visible = _visibleSongs(state, showInactive);

                        return CustomScrollView(
                          slivers: [
                            CupertinoSliverRefreshControl(onRefresh: _refresh),
                            _buildNavBar(context, showInactive),
                            if (state.songs.isEmpty)
                              const SliverFillRemaining(
                                child: EmptyStateView(
                                  icon: CupertinoIcons.music_mic,
                                  title: 'No songs yet',
                                  subtitle:
                                      'Add the songs your band plays to build setlists faster.',
                                ),
                              )
                            else if (visible.isEmpty)
                              SliverFillRemaining(
                                child: Center(
                                  child: Text(
                                    'No matching songs',
                                    style:
                                        TextStyle(color: context.secondaryText),
                                  ),
                                ),
                              )
                            else
                              SliverList(
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) {
                                    final song = visible[index];
                                    return _SongRow(
                                      song: song,
                                      showSeparator: index < visible.length - 1,
                                      onTap: () =>
                                          context.push('/songs/${song.id}'),
                                      onDelete: _isOwner
                                          ? () => _confirmDeleteSong(song)
                                          : null,
                                    );
                                  },
                                  childCount: visible.length,
                                ),
                              ),
                            const SliverToBoxAdapter(
                                child: SizedBox(height: 16)),
                          ],
                        );
                      },
                    ),
                  ),
                  _BottomSearchBar(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _query = v.trim()),
                    onAdd: _openCreateAndMaybeOpenDetail,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildNavBar(BuildContext context, bool showInactive) {
    return CupertinoSliverNavigationBar(
      largeTitle: const Text('Song list'),
      trailing: Semantics(
        button: true,
        label: 'Show inactive songs',
        child: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => ref
              .read(showInactiveSongsProvider.notifier)
              .update((v) => !v),
          child: Icon(
            showInactive ? CupertinoIcons.eye_fill : CupertinoIcons.eye_slash,
          ),
        ),
      ),
    );
  }
}

// ── Song row ──────────────────────────────────────────────────────────────────

class _SongRow extends StatelessWidget {
  const _SongRow({
    required this.song,
    required this.showSeparator,
    this.onTap,
    this.onDelete,
  });

  final Song song;
  final bool showSeparator;
  final VoidCallback? onTap;

  /// Null when the current user is not an owner of the selected band —
  /// long-press deletion is an owner-only affordance (server enforces too).
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: song.artist.isNotEmpty
          ? '${song.title}, by ${song.artist}'
          : song.title,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: onDelete,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: showSeparator
              ? BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: CupertinoColors.separator.resolveFrom(context),
                      width: 0.5,
                    ),
                  ),
                )
              : null,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w400),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (song.artist.isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        song.artist,
                        style: TextStyle(
                          fontSize: 13,
                          color: context.secondaryText,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (!song.active)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemGrey5.resolveFrom(context),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Inactive',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: context.secondaryText,
                    ),
                  ),
                ),
              if (song.songKey.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    song.songKey,
                    style: TextStyle(
                      fontSize: 13,
                      color: context.secondaryText,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(
                  CupertinoIcons.chevron_right,
                  size: 14,
                  color: context.tertiaryText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Bottom search bar (matches the library screen's) ─────────────────────────

class _BottomSearchBar extends StatelessWidget {
  const _BottomSearchBar({
    required this.controller,
    required this.onChanged,
    required this.onAdd,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground.resolveFrom(context),
        border: Border(
          top: BorderSide(
            color: CupertinoColors.separator.resolveFrom(context),
            width: 0.5,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: CupertinoSearchTextField(
              controller: controller,
              onChanged: onChanged,
              placeholder: 'Search',
            ),
          ),
          const SizedBox(width: 10),
          Semantics(
            button: true,
            enabled: onAdd != null,
            label: 'Add song',
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: onAdd,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: onAdd == null
                      ? CupertinoColors.systemGrey4.resolveFrom(context)
                      : CupertinoColors.activeBlue.resolveFrom(context),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(
                  CupertinoIcons.plus,
                  color: CupertinoColors.white,
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Write the segmented Library tab wrapper**

Create `lib/features/library/screens/library_tab_screen.dart`:

```dart
import 'package:flutter/cupertino.dart';
import '../../songs/screens/song_list_screen.dart';
import 'library_screen.dart';

enum LibraryTabSegment { songList, sheetMusic }

/// The Library tab: a segmented control switching between the band's song
/// list and the sheet-music library. The tab keeps its "Library" name and
/// icon; the Sheet music segment renders the existing [LibraryScreen]
/// unchanged below the segment.
class LibraryTabScreen extends StatefulWidget {
  const LibraryTabScreen({super.key});

  @override
  State<LibraryTabScreen> createState() => _LibraryTabScreenState();
}

class _LibraryTabScreenState extends State<LibraryTabScreen> {
  LibraryTabSegment _segment = LibraryTabSegment.songList;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: SizedBox(
                width: double.infinity,
                child: CupertinoSlidingSegmentedControl<LibraryTabSegment>(
                  groupValue: _segment,
                  onValueChanged: (value) {
                    if (value != null) setState(() => _segment = value);
                  },
                  children: const {
                    LibraryTabSegment.songList: Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Text('Song list'),
                    ),
                    LibraryTabSegment.sheetMusic: Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Text('Sheet music'),
                    ),
                  },
                ),
              ),
            ),
            Expanded(
              child: _segment == LibraryTabSegment.songList
                  ? const SongListScreen()
                  : const LibraryScreen(),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Wire the router**

In `lib/core/config/router.dart`:

1. Add imports next to the existing library imports (after line 35, `import '../../features/library/screens/library_screen.dart';`):

```dart
import '../../features/library/screens/library_tab_screen.dart';
import '../../features/songs/screens/song_list_screen.dart';
```

(The `library_screen.dart` import becomes unused once the `/library` builder changes — **delete it** to keep `flutter analyze` clean.)

2. The shell route currently reads:

```dart
          GoRoute(
            path: '/library',
            builder: (_, __) => const LibraryScreen(),
          ),
```

Change it to:

```dart
          GoRoute(
            path: '/library',
            builder: (_, __) => const LibraryTabScreen(),
          ),
```

3. Below the existing Library block at the end of the routes list, which currently reads:

```dart
      // Library — literal segment 'new' must precede the :chartId parameter
      // to prevent GoRouter from treating "new" as a chart ID.
      GoRoute(
        path: '/library/new',
        builder: (_, state) => CreateChartScreen(
          band: state.extra as BandSummary,
        ),
      ),
      GoRoute(
        path: '/library/:chartId',
        builder: (_, state) => ChartDetailScreen(
          bandId: state.extra as int,
          chartId: int.parse(state.pathParameters['chartId']!),
        ),
      ),
```

add (after the `/library/:chartId` route):

```dart
      // Songs — standalone list pushed from the Operations screen (no bottom
      // nav, like /media). Form and detail routes are added with their
      // screens; literal segments must precede parameterised ones.
      GoRoute(
        path: '/songs',
        builder: (_, __) => const SongListScreen(),
      ),
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `flutter test test/features/songs/screens/song_list_screen_test.dart test/features/library/screens/library_tab_screen_test.dart`
Expected: PASS (8 tests).

Run: `flutter test test/features/library/`
Expected: PASS — existing library tests unaffected (they mount `LibraryScreen` directly).

- [ ] **Step 7: Commit**

```bash
git add lib/features/songs/screens/song_list_screen.dart lib/features/library/screens/library_tab_screen.dart lib/core/config/router.dart test/features/songs/screens/song_list_screen_test.dart test/features/library/screens/library_tab_screen_test.dart
git commit -m "feat(songs): song list screen and segmented Library tab (Song list | Sheet music)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: Song form screen (create + edit)

**Files:**
- Create: `lib/features/songs/screens/song_form_screen.dart`
- Modify: `lib/core/config/router.dart` (add `/songs/new`, `/songs/:songId/edit`)
- Test: `test/features/songs/screens/song_form_screen_test.dart`

**Interfaces:**
- Consumes: `songsProvider` (`createSong`/`updateSong`, `genres` from state), `songsRepositoryProvider.lookupBpm`, `leadSingerOptionsProvider`, `RosterMember`, `Song`/`SongLeadSinger`/`SongRef`, `selectedBandProvider`.
- Produces: `class SongFormScreen extends ConsumerStatefulWidget { const SongFormScreen({super.key, this.existing}); final Song? existing; }` — pops with the saved `Song`. Routes: `/songs/new` (no extra), `/songs/:songId/edit` (extra = `Song`). Task 6's detail screen pushes the edit route.

- [ ] **Step 1: Write the failing widget tests**

Create `test/features/songs/screens/song_form_screen_test.dart`:

```dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/songs/screens/song_form_screen_test.dart`
Expected: FAIL — compile error, `song_form_screen.dart` does not exist.

- [ ] **Step 3: Write the form screen**

Create `lib/features/songs/screens/song_form_screen.dart` (form-section widgets follow the `create_chart_screen.dart` conventions — `_FormSection`, save-in-navbar, inline dismissible error banner):

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';
import 'package:tts_bandmate/shared/widgets/error_view.dart';

import '../../../shared/providers/selected_band_provider.dart';
import '../../personnel/data/models/roster.dart';
import '../data/models/song.dart';
import '../data/songs_repository.dart';
import '../providers/songs_provider.dart';

/// Full-screen modal form for creating ([existing] == null) or editing a
/// song, following the booking_form_screen.dart create/edit pattern.
/// Pops with the saved [Song] on success.
class SongFormScreen extends ConsumerStatefulWidget {
  const SongFormScreen({super.key, this.existing});

  final Song? existing;

  @override
  ConsumerState<SongFormScreen> createState() => _SongFormScreenState();
}

class _SongFormScreenState extends ConsumerState<SongFormScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _artistController;
  late final TextEditingController _keyController;
  late final TextEditingController _bpmController;
  late final TextEditingController _notesController;

  String _genre = '';
  int? _rating;
  int? _energy;
  bool _active = true;
  SongLeadSinger? _leadSinger;
  SongRef? _transitionSong;

  bool _isSaving = false;
  bool _isLookingUp = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _titleController = TextEditingController(text: existing?.title ?? '');
    _artistController = TextEditingController(text: existing?.artist ?? '');
    _keyController = TextEditingController(text: existing?.songKey ?? '');
    _bpmController = TextEditingController(
        text: (existing?.bpm ?? 0) > 0 ? existing!.bpm.toString() : '');
    _notesController = TextEditingController(text: existing?.notes ?? '');
    _genre = existing?.genre ?? '';
    _rating = existing?.rating;
    _energy = existing?.energy;
    _active = existing?.active ?? true;
    _leadSinger = existing?.leadSinger;
    _transitionSong = existing?.transitionSong;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    _keyController.dispose();
    _bpmController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  bool get _canSave => _titleController.text.trim().isNotEmpty && !_isSaving;

  Song _buildSong() {
    final bandId =
        widget.existing?.bandId ?? ref.read(selectedBandProvider).value ?? 0;
    return Song(
      id: widget.existing?.id ?? 0,
      bandId: bandId,
      title: _titleController.text.trim(),
      artist: _artistController.text.trim(),
      songKey: _keyController.text.trim(),
      genre: _genre,
      bpm: int.tryParse(_bpmController.text.trim()) ?? 0,
      notes: _notesController.text.trim(),
      rating: _rating,
      energy: _energy,
      active: _active,
      leadSinger: _leadSinger,
      transitionSong: _transitionSong,
      charts: widget.existing?.charts ?? const [],
    );
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      final draft = _buildSong();
      final saved = _isEdit
          ? await ref.read(songsProvider.notifier).updateSong(draft)
          : await ref.read(songsProvider.notifier).createSong(draft);
      if (mounted) Navigator.of(context).pop(saved);
    } catch (e) {
      setState(() {
        _isSaving = false;
        _error = ErrorView.friendlyMessage(e);
      });
    }
  }

  Future<void> _lookupBpm() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Enter a title before looking up the BPM.');
      return;
    }
    setState(() {
      _isLookingUp = true;
      _error = null;
    });
    try {
      final result = await ref.read(songsRepositoryProvider).lookupBpm(
            title: title,
            artist: _artistController.text.trim(),
          );
      final bpm = (result['bpm'] as num?)?.toInt();
      final key = result['song_key'] as String?;
      setState(() {
        if (bpm != null) _bpmController.text = bpm.toString();
        if (key != null &&
            key.isNotEmpty &&
            _keyController.text.trim().isEmpty) {
          _keyController.text = key;
        }
        if (bpm == null) _error = 'No BPM found for "$title".';
      });
    } catch (e) {
      setState(() => _error = ErrorView.friendlyMessage(e));
    } finally {
      if (mounted) setState(() => _isLookingUp = false);
    }
  }

  // ── Pickers ─────────────────────────────────────────────────────────────────

  Future<void> _pickGenre() async {
    final genres = ref.read(songsProvider).value?.genres ?? const <String>[];
    final result = await _showListPicker<String>(
      context,
      title: 'Genre',
      options: genres,
      labelOf: (g) => g,
    );
    if (result != null) setState(() => _genre = result.value ?? '');
  }

  Future<void> _pickLeadSinger() async {
    final members = await ref.read(leadSingerOptionsProvider.future);
    if (!mounted) return;
    final result = await _showListPicker<RosterMember>(
      context,
      title: 'Lead Singer',
      options: members,
      labelOf: (m) => m.name,
    );
    if (result != null) {
      setState(() => _leadSinger = result.value == null
          ? null
          : SongLeadSinger(id: result.value!.id, displayName: result.value!.name));
    }
  }

  Future<void> _pickTransitionSong() async {
    final songs = (ref.read(songsProvider).value?.songs ?? const <Song>[])
        .where((s) => s.id != widget.existing?.id)
        .toList();
    final result = await _showListPicker<Song>(
      context,
      title: 'Transition Song',
      options: songs,
      labelOf: (s) => s.artist.isNotEmpty ? '${s.title} — ${s.artist}' : s.title,
    );
    if (result != null) {
      setState(() => _transitionSong = result.value == null
          ? null
          : SongRef(
              id: result.value!.id,
              title: result.value!.title,
              artist: result.value!.artist,
            ));
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(_isEdit ? 'Edit Song' : 'New Song'),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        trailing: _isSaving
            ? const CupertinoActivityIndicator()
            : CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _canSave ? _save : null,
                child: Text(
                  'Save',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: _canSave
                        ? CupertinoColors.activeBlue.resolveFrom(context)
                        : CupertinoColors.tertiaryLabel.resolveFrom(context),
                  ),
                ),
              ),
      ),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth =
                constraints.maxWidth > 700 ? 700.0 : constraints.maxWidth;

            return Center(
              child: SizedBox(
                width: maxWidth,
                child: ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.only(top: 20, bottom: 40),
                  children: [
                    if (_error != null)
                      _ErrorBanner(
                        message: _error!,
                        onDismiss: () => setState(() => _error = null),
                      ),

                    // ── Identity ───────────────────────────────────────────
                    _FormSection(
                      children: [
                        _LabeledField(
                          label: 'Title',
                          child: CupertinoTextField(
                            controller: _titleController,
                            autofocus: !_isEdit,
                            placeholder: 'Required',
                            textInputAction: TextInputAction.next,
                            decoration: const BoxDecoration(),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        _FormDivider(),
                        _LabeledField(
                          label: 'Artist',
                          child: CupertinoTextField(
                            controller: _artistController,
                            placeholder: 'Optional',
                            textInputAction: TextInputAction.next,
                            decoration: const BoxDecoration(),
                          ),
                        ),
                      ],
                    ),

                    // ── Musical details ────────────────────────────────────
                    _FormSection(
                      children: [
                        _LabeledField(
                          label: 'Key',
                          child: CupertinoTextField(
                            controller: _keyController,
                            placeholder: 'e.g. E♭m',
                            textInputAction: TextInputAction.next,
                            decoration: const BoxDecoration(),
                          ),
                        ),
                        _FormDivider(),
                        _PickerRow(
                          label: 'Genre',
                          value: _genre.isEmpty ? null : _genre,
                          placeholder: 'None',
                          onTap: _pickGenre,
                        ),
                        _FormDivider(),
                        _LabeledField(
                          label: 'BPM',
                          child: Row(
                            children: [
                              Expanded(
                                child: CupertinoTextField(
                                  controller: _bpmController,
                                  placeholder: 'Optional',
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  decoration: const BoxDecoration(),
                                ),
                              ),
                              _isLookingUp
                                  ? const CupertinoActivityIndicator()
                                  : CupertinoButton(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8),
                                      minimumSize: Size.zero,
                                      onPressed: _lookupBpm,
                                      child: const Text(
                                        'Look up',
                                        style: TextStyle(fontSize: 15),
                                      ),
                                    ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    // ── People & flow ──────────────────────────────────────
                    _FormSection(
                      children: [
                        _PickerRow(
                          label: 'Lead singer',
                          value: _leadSinger?.displayName,
                          placeholder: 'None',
                          onTap: _pickLeadSinger,
                        ),
                        _FormDivider(),
                        _PickerRow(
                          label: 'Transition',
                          value: _transitionSong?.title,
                          placeholder: 'None',
                          onTap: _pickTransitionSong,
                        ),
                      ],
                    ),

                    // ── Rating / energy ────────────────────────────────────
                    _FormSection(
                      children: [
                        _StepperRow(
                          label: 'Rating',
                          value: _rating,
                          onChanged: (v) => setState(() => _rating = v),
                        ),
                        _FormDivider(),
                        _StepperRow(
                          label: 'Energy',
                          value: _energy,
                          onChanged: (v) => setState(() => _energy = v),
                        ),
                      ],
                    ),

                    // ── Notes ──────────────────────────────────────────────
                    _FormSection(
                      children: [
                        _LabeledField(
                          label: 'Notes',
                          alignLabelTop: true,
                          child: CupertinoTextField(
                            controller: _notesController,
                            placeholder: 'Optional',
                            maxLines: 3,
                            minLines: 3,
                            decoration: const BoxDecoration(),
                          ),
                        ),
                      ],
                    ),

                    // ── Active toggle ──────────────────────────────────────
                    _FormSection(
                      children: [
                        _SwitchRow(
                          label: 'Active',
                          subtitle:
                              'Inactive songs are hidden from search and the setlist picker',
                          value: _active,
                          onChanged: (v) => setState(() => _active = v),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ── List picker sheet ─────────────────────────────────────────────────────────

/// Wrapper distinguishing "picked None" ([value] == null) from a dismissed
/// sheet (the outer Future resolves to null).
class _PickerSelection<T> {
  const _PickerSelection(this.value);
  final T? value;
}

Future<_PickerSelection<T>?> _showListPicker<T>(
  BuildContext context, {
  required String title,
  required List<T> options,
  required String Function(T) labelOf,
}) {
  return showCupertinoModalPopup<_PickerSelection<T>>(
    context: context,
    builder: (sheetCtx) => Container(
      height: MediaQuery.of(sheetCtx).size.height * 0.6,
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground.resolveFrom(sheetCtx),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(
                title,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  _PickerOptionRow(
                    label: 'None',
                    onTap: () => Navigator.of(sheetCtx)
                        .pop(_PickerSelection<T>(null)),
                  ),
                  for (final option in options)
                    _PickerOptionRow(
                      label: labelOf(option),
                      onTap: () => Navigator.of(sheetCtx)
                          .pop(_PickerSelection<T>(option)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _PickerOptionRow extends StatelessWidget {
  const _PickerOptionRow({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: CupertinoColors.separator.resolveFrom(context),
              width: 0.5,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 15, color: context.primaryText),
        ),
      ),
    );
  }
}

// ── Form building blocks (create_chart_screen.dart conventions) ───────────────

class _FormSection extends StatelessWidget {
  const _FormSection({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(
        color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: children),
    );
  }
}

class _FormDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 0.5,
      margin: const EdgeInsets.only(left: 16),
      color: CupertinoColors.separator.resolveFrom(context),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.child,
    this.alignLabelTop = false,
  });

  final String label;
  final Widget child;
  final bool alignLabelTop;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment:
            alignLabelTop ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 100,
            child: Padding(
              padding:
                  alignLabelTop ? const EdgeInsets.only(top: 4) : EdgeInsets.zero,
              child: Text(
                label,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// A tappable row for sheet-based pickers — label left, current value (or a
/// dimmed placeholder) and a chevron right.
class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.label,
    required this.value,
    required this.placeholder,
    required this.onTap,
  });

  final String label;
  final String? value;
  final String placeholder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label, ${value ?? placeholder}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 100,
                child: Text(
                  label,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w400),
                ),
              ),
              Expanded(
                child: Text(
                  value ?? placeholder,
                  style: TextStyle(
                    fontSize: 16,
                    color: value == null
                        ? context.secondaryText
                        : context.primaryText,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                CupertinoIcons.chevron_right,
                size: 14,
                color: context.tertiaryText,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A 1–10 stepper. Minus at 1 clears back to unset (null); plus from unset
/// starts at 1 and caps at 10.
class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
            ),
          ),
          Expanded(
            child: Text(
              value == null ? 'Not set' : '$value / 10',
              style: TextStyle(
                fontSize: 16,
                color:
                    value == null ? context.secondaryText : context.primaryText,
              ),
            ),
          ),
          Semantics(
            button: true,
            label: 'Decrease $label',
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: Size.zero,
              onPressed: value == null
                  ? null
                  : () => onChanged(value == 1 ? null : value! - 1),
              child: const Icon(CupertinoIcons.minus_circle, size: 24),
            ),
          ),
          Semantics(
            button: true,
            label: 'Increase $label',
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: Size.zero,
              onPressed: (value ?? 0) >= 10
                  ? null
                  : () => onChanged(value == null ? 1 : value! + 1),
              child: const Icon(CupertinoIcons.plus_circle, size: 24),
            ),
          ),
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 16)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.secondaryText,
                    ),
                  ),
                ],
              ],
            ),
          ),
          CupertinoSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: CupertinoColors.systemRed.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: CupertinoColors.systemRed.resolveFrom(context),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Icon(
            CupertinoIcons.exclamationmark_circle,
            size: 16,
            color: CupertinoColors.systemRed.resolveFrom(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13,
                color: CupertinoColors.systemRed.resolveFrom(context),
              ),
            ),
          ),
          CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            onPressed: onDismiss,
            child: Icon(
              CupertinoIcons.xmark,
              size: 14,
              color: CupertinoColors.systemRed.resolveFrom(context),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Add the routes**

In `lib/core/config/router.dart`, add the import next to the song list import from Task 4:

```dart
import '../../features/songs/data/models/song.dart';
import '../../features/songs/screens/song_form_screen.dart';
```

Then extend the Songs route block from Task 4. It currently reads:

```dart
      // Songs — standalone list pushed from the Operations screen (no bottom
      // nav, like /media). Form and detail routes are added with their
      // screens; literal segments must precede parameterised ones.
      GoRoute(
        path: '/songs',
        builder: (_, __) => const SongListScreen(),
      ),
```

Change it to:

```dart
      // Songs — standalone list pushed from the Operations screen (no bottom
      // nav, like /media). Literal segment 'new' must precede the :songId
      // parameter to prevent GoRouter from treating "new" as a song ID.
      GoRoute(
        path: '/songs',
        builder: (_, __) => const SongListScreen(),
      ),
      GoRoute(
        path: '/songs/new',
        builder: (_, __) => const SongFormScreen(),
      ),
      GoRoute(
        path: '/songs/:songId/edit',
        builder: (_, state) => SongFormScreen(
          existing: state.extra as Song,
        ),
      ),
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/features/songs/screens/song_form_screen_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/features/songs/screens/song_form_screen.dart lib/core/config/router.dart test/features/songs/screens/song_form_screen_test.dart
git commit -m "feat(songs): song create/edit form with BPM lookup, pickers, and steppers

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: Song detail screen

**Files:**
- Create: `lib/features/songs/screens/song_detail_screen.dart`
- Modify: `lib/core/config/router.dart` (add `/songs/:songId`)
- Test: `test/features/songs/screens/song_detail_screen_test.dart`

**Interfaces:**
- Consumes: `songsProvider` (the detail renders from list state — there is no per-song GET endpoint, so edits made via `updateSong` are reflected immediately), `Song`, routes `/songs/:songId/edit` (Task 5) and `/library/:chartId` (existing — expects `extra: bandId as int`).
- Produces: `class SongDetailScreen extends ConsumerWidget { const SongDetailScreen({super.key, required this.songId}); final int songId; }`; route `/songs/:songId` (registered AFTER `/songs/new`).

- [ ] **Step 1: Write the failing widget tests**

Create `test/features/songs/screens/song_detail_screen_test.dart`:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tts_bandmate/features/songs/data/models/song.dart';
import 'package:tts_bandmate/features/songs/data/songs_repository.dart';
import 'package:tts_bandmate/features/songs/providers/songs_provider.dart';
import 'package:tts_bandmate/features/songs/screens/song_detail_screen.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';

class _StubBand extends SelectedBandNotifier {
  @override
  Future<int?> build() async => 1;
}

class _FakeRepo implements SongsRepository {
  _FakeRepo(this._songs);
  final List<Song> _songs;

  @override
  Future<({List<Song> songs, List<String> genres})> getSongs(
    int bandId, {
    bool includeInactive = false,
  }) async =>
      (songs: _songs, genres: const <String>[]);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

String? pushedChartLocation;
Object? pushedChartExtra;

Widget _harness(List<Song> songs, {int songId = 7}) {
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => SongDetailScreen(songId: songId)),
    GoRoute(
      path: '/library/:chartId',
      builder: (_, state) {
        pushedChartLocation = state.uri.path;
        pushedChartExtra = state.extra;
        return const CupertinoPageScaffold(child: Text('chart detail'));
      },
    ),
  ]);
  return ProviderScope(
    overrides: [
      selectedBandProvider.overrideWith(_StubBand.new),
      songsRepositoryProvider.overrideWithValue(_FakeRepo(songs)),
    ],
    child: CupertinoApp.router(routerConfig: router),
  );
}

const _song = Song(
  id: 7,
  bandId: 2,
  title: 'September',
  artist: 'Earth, Wind & Fire',
  songKey: 'A',
  genre: 'Funk',
  bpm: 126,
  notes: 'Watch the horn break',
  rating: 9,
  energy: 10,
  leadSinger: SongLeadSinger(id: 3, displayName: 'Alex'),
  transitionSong: SongRef(id: 9, title: 'Boogie Wonderland'),
  charts: [SongChartSummary(id: 11, title: 'September - Horns')],
);

void main() {
  setUp(() {
    pushedChartLocation = null;
    pushedChartExtra = null;
  });

  testWidgets('renders every populated field', (tester) async {
    await tester.pumpWidget(_harness(const [_song]));
    await tester.pumpAndSettle();

    expect(find.text('September'), findsOneWidget);
    expect(find.text('Earth, Wind & Fire'), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
    expect(find.text('Funk'), findsOneWidget);
    expect(find.text('126'), findsOneWidget);
    expect(find.text('9 / 10'), findsOneWidget);
    expect(find.text('10 / 10'), findsOneWidget);
    expect(find.text('Alex'), findsOneWidget);
    expect(find.text('Boogie Wonderland'), findsOneWidget);
    expect(find.text('Watch the horn break'), findsOneWidget);
    expect(find.text('SHEET MUSIC'), findsOneWidget);
    expect(find.text('September - Horns'), findsOneWidget);
  });

  testWidgets('tapping a linked chart pushes the chart detail route',
      (tester) async {
    await tester.pumpWidget(_harness(const [_song]));
    await tester.pumpAndSettle();

    await tester.tap(find.text('September - Horns'));
    await tester.pumpAndSettle();

    expect(pushedChartLocation, '/library/11');
    expect(pushedChartExtra, 2); // the song's bandId
  });

  testWidgets('unknown song id shows a not-found state', (tester) async {
    await tester.pumpWidget(_harness(const [_song], songId: 999));
    await tester.pumpAndSettle();

    expect(find.text('Song not found'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/songs/screens/song_detail_screen_test.dart`
Expected: FAIL — compile error, `song_detail_screen.dart` does not exist.

- [ ] **Step 3: Write the detail screen**

Create `lib/features/songs/screens/song_detail_screen.dart`:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';
import 'package:tts_bandmate/shared/widgets/empty_state_view.dart';
import 'package:tts_bandmate/shared/widgets/error_view.dart';

import '../data/models/song.dart';
import '../providers/songs_provider.dart';

/// Read-only song detail. Renders from [songsProvider] list state (there is
/// no per-song GET endpoint), so edits saved by the form show immediately.
class SongDetailScreen extends ConsumerWidget {
  const SongDetailScreen({super.key, required this.songId});

  final int songId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songsAsync = ref.watch(songsProvider);

    return songsAsync.when(
      loading: () => const CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(middle: Text('Song')),
        child: Center(child: CupertinoActivityIndicator()),
      ),
      error: (e, _) => CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(middle: Text('Song')),
        child: ErrorView(
          message: ErrorView.friendlyMessage(e),
          onRetry: () => ref.read(songsProvider.notifier).refresh(),
        ),
      ),
      data: (state) {
        final song = state.songs.where((s) => s.id == songId).firstOrNull;
        if (song == null) {
          return const CupertinoPageScaffold(
            navigationBar: CupertinoNavigationBar(middle: Text('Song')),
            child: EmptyStateView(
              icon: CupertinoIcons.music_mic,
              title: 'Song not found',
              subtitle: 'It may have been deleted on another device.',
            ),
          );
        }
        return _SongDetailBody(song: song);
      },
    );
  }
}

class _SongDetailBody extends StatelessWidget {
  const _SongDetailBody({required this.song});

  final Song song;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(song.title),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => context.push('/songs/${song.id}/edit', extra: song),
          child: const Text('Edit'),
        ),
      ),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth =
                constraints.maxWidth > 700 ? 700.0 : constraints.maxWidth;
            return Center(
              child: SizedBox(
                width: maxWidth,
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  children: [
                    const _SectionHeader(label: 'Details'),
                    _DetailCard(song: song),
                    if (song.notes.isNotEmpty) ...[
                      const _SectionHeader(label: 'Notes'),
                      _NotesCard(notes: song.notes),
                    ],
                    const _SectionHeader(label: 'Sheet music'),
                    if (song.charts.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Text(
                          'No sheet music linked to this song yet.',
                          style: TextStyle(
                            fontSize: 14,
                            color: context.secondaryText,
                          ),
                        ),
                      )
                    else
                      ...song.charts.map(
                        (chart) => _ChartRow(
                          chart: chart,
                          onTap: () => context.push(
                            '/library/${chart.id}',
                            extra: song.bandId,
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: context.secondaryText,
        ),
      ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.song});

  final Song song;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[
      if (song.artist.isNotEmpty) _MetaRow(label: 'Artist', value: song.artist),
      if (song.songKey.isNotEmpty) _MetaRow(label: 'Key', value: song.songKey),
      if (song.genre.isNotEmpty) _MetaRow(label: 'Genre', value: song.genre),
      if (song.bpm > 0) _MetaRow(label: 'BPM', value: song.bpm.toString()),
      if (song.rating != null)
        _MetaRow(label: 'Rating', value: '${song.rating} / 10'),
      if (song.energy != null)
        _MetaRow(label: 'Energy', value: '${song.energy} / 10'),
      if (song.leadSinger != null)
        _MetaRow(label: 'Lead singer', value: song.leadSinger!.displayName),
      if (song.transitionSong != null)
        _MetaRow(label: 'Transition', value: song.transitionSong!.title),
      _MetaRow(label: 'Status', value: song.active ? 'Active' : 'Inactive'),
    ];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            rows[i],
            if (i < rows.length - 1)
              Container(
                height: 0.5,
                margin: const EdgeInsets.only(left: 16),
                color: CupertinoColors.separator.resolveFrom(context),
              ),
          ],
        ],
      ),
    );
  }
}

class _NotesCard extends StatelessWidget {
  const _NotesCard({required this.notes});

  final String notes;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(notes, style: const TextStyle(fontSize: 14)),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(fontSize: 14, color: context.secondaryText),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );
  }
}

class _ChartRow extends StatelessWidget {
  const _ChartRow({required this.chart, required this.onTap});

  final SongChartSummary chart;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${chart.title}. Opens the sheet music detail.',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color:
                CupertinoColors.tertiarySystemBackground.resolveFrom(context),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                CupertinoIcons.doc_text,
                size: 18,
                color: context.secondaryText,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  chart.title,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                CupertinoIcons.chevron_right,
                size: 14,
                color: context.tertiaryText,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Add the route**

In `lib/core/config/router.dart`, add the import next to the form screen import:

```dart
import '../../features/songs/screens/song_detail_screen.dart';
```

Then in the Songs route block, insert **after** `/songs/:songId/edit` (keeping `/songs/new` first — literal before parameterised):

```dart
      GoRoute(
        path: '/songs/:songId',
        builder: (_, state) => SongDetailScreen(
          songId: int.parse(state.pathParameters['songId']!),
        ),
      ),
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/features/songs/screens/song_detail_screen_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/features/songs/screens/song_detail_screen.dart lib/core/config/router.dart test/features/songs/screens/song_detail_screen_test.dart
git commit -m "feat(songs): song detail screen with linked sheet music section

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: Chart↔song linking (model, repository, create form, detail relink)

**Files:**
- Modify: `lib/features/library/data/models/chart.dart`
- Modify: `lib/features/library/data/library_repository.dart`
- Modify: `lib/features/library/providers/library_provider.dart` (`createChart` passthrough + `song` on the stamped copy)
- Modify: `lib/features/library/screens/create_chart_screen.dart`
- Modify: `lib/features/library/screens/chart_detail_screen.dart`
- Test: `test/features/library/data/models/chart_test.dart` (extend)
- Test: `test/features/library/data/library_repository_test.dart` (new)

**Interfaces:**
- Consumes: `bandSongsProvider` (Task 3), `Song` (Task 1), backend `PATCH /api/mobile/bands/{band}/charts/{chart}` + `"song": {id, title, artist}|null` in chart payloads, existing `ApiEndpoints.mobileBandChart(bandId, chartId)`.
- Produces:
  - `class ChartSongRef { int id; String title; String artist; }` and `Chart.song` (`ChartSongRef?`, optional constructor param so existing call sites compile unchanged).
  - `LibraryRepository.createChart(..., int? songId)` (new optional named param).
  - `LibraryRepository.updateChartSong(int bandId, int chartId, {required int? songId}) → Future<Chart>` (null unlinks).
  - `LibraryNotifier.createChart(..., int? songId)` passthrough.

- [ ] **Step 1: Write the failing tests**

Append to `test/features/library/data/models/chart_test.dart` (inside `main()`, after the existing groups):

```dart
  group('Chart.fromJson — song block', () {
    test('parses the linked song', () {
      final chart = Chart.fromJson({
        'id': 1,
        'band_id': 7,
        'title': 'Horn Chart',
        'composer': '',
        'description': '',
        'price': 0,
        'public': false,
        'uploads_count': 0,
        'song': {'id': 5, 'title': 'September', 'artist': 'EWF'},
      });

      expect(chart.song, isNotNull);
      expect(chart.song!.id, 5);
      expect(chart.song!.title, 'September');
      expect(chart.song!.artist, 'EWF');
    });

    test('null and missing song both parse as null', () {
      final withNull = Chart.fromJson({
        'id': 1,
        'band_id': 7,
        'title': 'A',
        'song': null,
      });
      final missing = Chart.fromJson({
        'id': 2,
        'band_id': 7,
        'title': 'B',
      });

      expect(withNull.song, isNull);
      expect(missing.song, isNull);
    });
  });
```

Create `test/features/library/data/library_repository_test.dart`:

```dart
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/library/data/library_repository.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.responder);

  final Future<ResponseBody> Function(RequestOptions) responder;

  @override
  Future<ResponseBody> fetch(RequestOptions options, _, __) => responder(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int status, Object body) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        'content-type': ['application/json'],
      },
    );

Map<String, dynamic> _chartJson({Map<String, dynamic>? song}) => {
      'id': 3,
      'band_id': 1,
      'title': 'Horn Chart',
      'composer': '',
      'description': '',
      'price': 0,
      'public': false,
      'uploads_count': 0,
      'song': song,
    };

void main() {
  late Dio dio;

  setUp(() {
    dio = Dio();
  });

  test('createChart includes song_id when provided', () async {
    Map<String, dynamic>? capturedBody;
    dio.httpClientAdapter = _FakeAdapter((req) async {
      capturedBody = req.data as Map<String, dynamic>;
      expect(req.path, '/api/mobile/bands/1/charts');
      expect(req.method, 'POST');
      return _json(201, {
        'chart': _chartJson(song: {'id': 5, 'title': 'September', 'artist': ''}),
      });
    });

    final repo = LibraryRepository(dio);
    final chart = await repo.createChart(1, title: 'Horn Chart', songId: 5);

    expect(capturedBody!['song_id'], 5);
    expect(chart.song!.id, 5);
  });

  test('createChart omits song_id when null', () async {
    dio.httpClientAdapter = _FakeAdapter((req) async {
      expect((req.data as Map<String, dynamic>).containsKey('song_id'), false);
      return _json(201, {'chart': _chartJson()});
    });

    final repo = LibraryRepository(dio);
    await repo.createChart(1, title: 'Horn Chart');
  });

  test('updateChartSong PATCHes the chart with song_id', () async {
    dio.httpClientAdapter = _FakeAdapter((req) async {
      expect(req.path, '/api/mobile/bands/1/charts/3');
      expect(req.method, 'PATCH');
      expect(req.data, {'song_id': 5});
      return _json(200, {
        'chart': _chartJson(song: {'id': 5, 'title': 'September', 'artist': ''}),
      });
    });

    final repo = LibraryRepository(dio);
    final chart = await repo.updateChartSong(1, 3, songId: 5);

    expect(chart.song!.title, 'September');
  });

  test('updateChartSong with null unlinks', () async {
    dio.httpClientAdapter = _FakeAdapter((req) async {
      expect(req.data, {'song_id': null});
      return _json(200, {'chart': _chartJson()});
    });

    final repo = LibraryRepository(dio);
    final chart = await repo.updateChartSong(1, 3, songId: null);

    expect(chart.song, isNull);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/library/data/`
Expected: FAIL — `Chart` has no `song` getter; `updateChartSong`/`songId` do not exist.

- [ ] **Step 3: Extend the Chart model**

In `lib/features/library/data/models/chart.dart`, add above `class Chart`:

```dart
/// Linked-song block carried on a [Chart] (`"song": {id, title, artist}|null`).
class ChartSongRef {
  const ChartSongRef({required this.id, required this.title, this.artist = ''});

  final int id;
  final String title;
  final String artist;

  factory ChartSongRef.fromJson(Map<String, dynamic> json) => ChartSongRef(
        id: (json['id'] as num).toInt(),
        title: json['title'] as String? ?? '',
        artist: json['artist'] as String? ?? '',
      );
}
```

In `class Chart`: add the field and optional constructor param (after `band`):

```dart
  final ChartSongRef? song;
```

```dart
    this.band,
    this.song,
```

And in `Chart.fromJson`, after the `band:` entry:

```dart
        song: json['song'] is Map<String, dynamic>
            ? ChartSongRef.fromJson(json['song'] as Map<String, dynamic>)
            : null,
```

- [ ] **Step 4: Extend the repository and provider**

In `lib/features/library/data/library_repository.dart`, change `createChart`'s signature and body — add the `songId` param and body entry:

```dart
  /// Creates a new chart for [bandId]. [songId] optionally links the chart
  /// to a song in the same band.
  Future<Chart> createChart(
    int bandId, {
    required String title,
    String? composer,
    String? description,
    double? price,
    bool isPublic = false,
    int? songId,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.mobileBandCharts(bandId),
      data: {
        'title': title,
        if (composer != null && composer.isNotEmpty) 'composer': composer,
        if (description != null && description.isNotEmpty)
          'description': description,
        if (price != null) 'price': price,
        'public': isPublic,
        if (songId != null) 'song_id': songId,
      },
    );

    final data = response.data!;
    return Chart.fromJson(data['chart'] as Map<String, dynamic>);
  }
```

Add after `deleteChart`:

```dart
  /// Links ([songId] set) or unlinks ([songId] null) a song on a chart via
  /// PATCH /api/mobile/bands/{band}/charts/{chart}.
  Future<Chart> updateChartSong(
    int bandId,
    int chartId, {
    required int? songId,
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      ApiEndpoints.mobileBandChart(bandId, chartId),
      data: {'song_id': songId},
    );
    return Chart.fromJson(response.data!['chart'] as Map<String, dynamic>);
  }
```

In `lib/features/library/providers/library_provider.dart`, `LibraryNotifier.createChart`: add `int? songId,` to the named params, pass `songId: songId,` in the `repo.createChart(...)` call, and add `song: created.song,` to the `stamped = Chart(...)` construction (alongside the other copied fields).

- [ ] **Step 5: Run the data tests**

Run: `flutter test test/features/library/data/ test/features/library/providers/`
Expected: PASS (existing tests still green — `song` is optional everywhere).

- [ ] **Step 6: Add the Linked song picker to the create form**

In `lib/features/library/screens/create_chart_screen.dart`:

1. Add imports after the existing ones (`flutter_riverpod` is already imported by this file — do not duplicate it):

```dart
import '../../songs/data/models/song.dart';
import '../../songs/providers/songs_provider.dart';
```

2. Add state to `_CreateChartScreenState` next to `bool _isPublic = false;`:

```dart
  Song? _linkedSong;
```

3. Pass it through in `_save()` — the `createChart(...)` call gains:

```dart
            songId: _linkedSong?.id,
```

4. In the template, inside the "Optional details group" `_FormSection`, after the Price `_LabeledField` add:

```dart
                        _FormDivider(),
                        Consumer(
                          builder: (context, ref, _) {
                            final songsAsync =
                                ref.watch(bandSongsProvider(widget.band.id));
                            final songs = songsAsync.value ?? const <Song>[];
                            return _LinkedSongRow(
                              linkedSong: _linkedSong,
                              onTap: songs.isEmpty
                                  ? null
                                  : () async {
                                      final picked =
                                          await _showLinkedSongPicker(
                                              context, songs);
                                      if (picked != null) {
                                        setState(() =>
                                            _linkedSong = picked.value);
                                      }
                                    },
                            );
                          },
                        ),
```

5. Add these widgets/helpers at the bottom of the file (with the other private widgets):

```dart
// ── Linked song picker ────────────────────────────────────────────────────────

/// Wrapper distinguishing "picked None" ([value] == null) from a dismissed
/// sheet (the Future resolves to null).
class _LinkedSongSelection {
  const _LinkedSongSelection(this.value);
  final Song? value;
}

Future<_LinkedSongSelection?> _showLinkedSongPicker(
  BuildContext context,
  List<Song> songs,
) {
  return showCupertinoModalPopup<_LinkedSongSelection>(
    context: context,
    builder: (sheetCtx) => Container(
      height: MediaQuery.of(sheetCtx).size.height * 0.6,
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground.resolveFrom(sheetCtx),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(
                'Linked song',
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  _LinkedSongOption(
                    label: 'None',
                    onTap: () => Navigator.of(sheetCtx)
                        .pop(const _LinkedSongSelection(null)),
                  ),
                  for (final song in songs)
                    _LinkedSongOption(
                      label: song.artist.isNotEmpty
                          ? '${song.title} — ${song.artist}'
                          : song.title,
                      onTap: () => Navigator.of(sheetCtx)
                          .pop(_LinkedSongSelection(song)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _LinkedSongOption extends StatelessWidget {
  const _LinkedSongOption({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: CupertinoColors.separator.resolveFrom(context),
              width: 0.5,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 15, color: context.primaryText),
        ),
      ),
    );
  }
}

/// The tappable "Linked song" form row.
class _LinkedSongRow extends StatelessWidget {
  const _LinkedSongRow({required this.linkedSong, required this.onTap});

  final Song? linkedSong;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Linked song, ${linkedSong?.title ?? 'None'}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 100,
                child: Text(
                  'Linked song',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w400),
                ),
              ),
              Expanded(
                child: Text(
                  linkedSong?.title ?? 'None',
                  style: TextStyle(
                    fontSize: 16,
                    color: linkedSong == null
                        ? context.secondaryText
                        : context.primaryText,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                CupertinoIcons.chevron_right,
                size: 14,
                color: context.tertiaryText,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 7: Show + relink the song on the chart detail screen**

In `lib/features/library/screens/chart_detail_screen.dart`:

1. Add imports:

```dart
import '../../songs/data/models/song.dart';
import '../../songs/providers/songs_provider.dart';
```

2. In `_MetadataCard.build`, after the composer row block:

```dart
    if (chart.song != null) {
      final s = chart.song!;
      rows.add(_MetaRow(
        label: 'Song',
        value: s.artist.isNotEmpty ? '${s.title} — ${s.artist}' : s.title,
      ));
    }
```

3. In `_ChartDetailBody.build`, after `_MetadataCard(chart: chart),` add a linked-song section:

```dart
                    const _SectionHeader(label: 'Linked song'),
                    _LinkedSongEditor(
                      chart: chart,
                      bandId: bandId,
                      chartId: chartId,
                    ),
```

4. Add the editor widget at the bottom of the file:

```dart
// ── Linked song editor ────────────────────────────────────────────────────────

/// Shows the currently linked song and lets the user relink/unlink via the
/// PATCH chart endpoint. Uses [bandSongsProvider] because the chart's band
/// can differ from the selected band.
class _LinkedSongEditor extends ConsumerWidget {
  const _LinkedSongEditor({
    required this.chart,
    required this.bandId,
    required this.chartId,
  });

  final Chart chart;
  final int bandId;
  final int chartId;

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    final List<Song> songs;
    try {
      songs = await ref.read(bandSongsProvider(bandId).future);
    } catch (e) {
      if (context.mounted) _showError(context, e);
      return;
    }
    if (!context.mounted) return;

    final picked = await showCupertinoModalPopup<({Song? song})>(
      context: context,
      builder: (sheetCtx) => Container(
        height: MediaQuery.of(sheetCtx).size.height * 0.6,
        decoration: BoxDecoration(
          color: CupertinoColors.systemBackground.resolveFrom(sheetCtx),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Text(
                  'Linked song',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
              ),
              Expanded(
                child: ListView(
                  children: [
                    _PickerRow(
                      label: 'None',
                      onTap: () =>
                          Navigator.of(sheetCtx).pop((song: null)),
                    ),
                    for (final song in songs)
                      _PickerRow(
                        label: song.artist.isNotEmpty
                            ? '${song.title} — ${song.artist}'
                            : song.title,
                        onTap: () =>
                            Navigator.of(sheetCtx).pop((song: song)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (picked == null || !context.mounted) return;

    try {
      await ref.read(libraryRepositoryProvider).updateChartSong(
            bandId,
            chartId,
            songId: picked.song?.id,
          );
      ref.invalidate(
          chartDetailProvider((bandId: bandId, chartId: chartId)));
    } catch (e) {
      if (context.mounted) _showError(context, e);
    }
  }

  void _showError(BuildContext context, Object e) {
    showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Could Not Update Link'),
        content: Text(e.toString()),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final linked = chart.song;
    return Semantics(
      button: true,
      label:
          'Linked song, ${linked?.title ?? 'None'}. Tap to change.',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _pick(context, ref),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color:
                CupertinoColors.tertiarySystemBackground.resolveFrom(context),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  linked == null
                      ? 'None — tap to link a song'
                      : (linked.artist.isNotEmpty
                          ? '${linked.title} — ${linked.artist}'
                          : linked.title),
                  style: TextStyle(
                    fontSize: 14,
                    color: linked == null
                        ? context.secondaryText
                        : context.primaryText,
                  ),
                ),
              ),
              Icon(
                CupertinoIcons.chevron_right,
                size: 14,
                color: context.tertiaryText,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: CupertinoColors.separator.resolveFrom(context),
              width: 0.5,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 15, color: context.primaryText),
        ),
      ),
    );
  }
}
```

- [ ] **Step 8: Run the library and songs suites + analyzer**

Run: `flutter test test/features/library/ test/features/songs/`
Expected: PASS.
Run: `flutter analyze`
Expected: no new issues.

- [ ] **Step 9: Commit**

```bash
git add lib/features/library lib/features/songs test/features/library
git commit -m "feat(library): songs↔sheet-music linking on create form and detail screen

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 8: Operations screen "Song list" NavRow

**Files:**
- Modify: `lib/features/more/screens/operations_screen.dart`
- Test: `test/features/more/operations_settings_screens_test.dart` (extend)

**Interfaces:**
- Consumes: `NavRow` (`lib/shared/widgets/nav_row.dart`), route `/songs` (Task 4).
- Produces: a `Song list` row on the Operations screen for all members.

- [ ] **Step 1: Write the failing test**

In `test/features/more/operations_settings_screens_test.dart`, the first test currently asserts this label list:

```dart
    for (final label in [
      'Bookings',
      'Finances',
      'Rehearsals',
      'Personnel',
      'Media',
    ]) {
```

Add `'Song list',` after `'Rehearsals',` in that list (one scenario per testWidgets is the file's idiom — extending the existing owner scenario is enough; the row is not owner-gated so no new scenario is required).

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/more/operations_settings_screens_test.dart`
Expected: FAIL — `Expected: exactly one matching candidate ... 'Song list'`.

- [ ] **Step 3: Add the NavRow**

In `lib/features/more/screens/operations_screen.dart`, the rows currently read (quoted from the file):

```dart
          NavRow(
            title: 'Rehearsals',
            leading: Icon(CupertinoIcons.person_2,
                size: 22, color: context.secondaryText),
            onTap: () => context.push('/rehearsals'),
          ),
          if (isOwner)
```

Insert between the Rehearsals row and the `if (isOwner)` Personnel row:

```dart
          NavRow(
            title: 'Song list',
            leading: Icon(CupertinoIcons.music_note_2,
                size: 22, color: context.secondaryText),
            onTap: () => context.push('/songs'),
          ),
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/more/operations_settings_screens_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/more/screens/operations_screen.dart test/features/more/operations_settings_screens_test.dart
git commit -m "feat(nav): Song list row on the Operations screen

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 9: Relabel user-facing "Chart(s)" copy to "Sheet music"

Display copy only — identifiers, routes (`/library/...`), file names, provider names, the `charts` permission key, and API paths all stay unchanged. The existing upload-type label `'Sheet Music'` in `chart_detail_screen.dart` (`_kUploadTypes`) stays as-is.

**Files:**
- Modify: `lib/features/library/screens/library_screen.dart`
- Modify: `lib/features/library/screens/create_chart_screen.dart`
- Modify: `lib/features/library/widgets/create_chart_sheet.dart`
- Modify: `lib/features/library/screens/chart_detail_screen.dart`
- Modify: `lib/features/search/screens/search_screen.dart`
- Modify: `lib/features/events/screens/event_detail_screen.dart`
- Modify: `lib/features/band_settings/screens/member_permissions_screen.dart`

**Interfaces:**
- Consumes: nothing new. Produces: copy changes only — no test relies on the old strings (verified: `grep -rn "New Chart\|Delete Chart\|No charts\|Add chart\|Search songs, charts" test/` returns nothing today; re-verify in Step 3).

- [ ] **Step 1: Apply the exact string edits**

`lib/features/library/screens/library_screen.dart`:
- `title: const Text('Delete Chart')` → `title: const Text('Delete Sheet Music')`
- `title: 'No charts in your library'` → `title: 'No sheet music in your library'`
- `'Charts added to any of your bands will appear here.'` → `'Sheet music added to any of your bands will appear here.'`
- `Text('No matching charts',` → `Text('No matching sheet music',`
- `label: 'Add chart',` (bottom-bar Semantics) → `label: 'Add sheet music',`
- `title: const Text('Could not create chart'),` → `title: const Text('Could not create sheet music'),`

`lib/features/library/screens/create_chart_screen.dart`:
- `middle: const Text('New Chart'),` → `middle: const Text('New Sheet Music'),`

`lib/features/library/widgets/create_chart_sheet.dart`:
- `'Add chart to'` → `'Add sheet music to'`

`lib/features/library/screens/chart_detail_screen.dart` (the loading and error nav bars):
- both `CupertinoNavigationBar(middle: Text('Chart'))` → `CupertinoNavigationBar(middle: Text('Sheet Music'))`

`lib/features/search/screens/search_screen.dart`:
- `items.add(const _SectionHeader('Charts'));` → `items.add(const _SectionHeader('Sheet music'));`
- `placeholder: 'Search songs, charts, bookings...',` → `placeholder: 'Search songs, sheet music, bookings...',`
- `message: 'Search songs, charts, bookings, and contacts',` → `message: 'Search songs, sheet music, bookings, and contacts',`

`lib/features/events/screens/event_detail_screen.dart` (the performance charts section heading, ~line 889):
- `Text('Charts',` → `Text('Sheet music',`

`lib/features/band_settings/screens/member_permissions_screen.dart` (display label only — the `'charts'` key MUST stay):
- `('Charts', 'charts'),` → `('Sheet music', 'charts'),`

- [ ] **Step 2: Sweep for stragglers**

Run:

```bash
grep -rn "Chart" lib --include="*.dart" | grep -E "Text\('|label: '|title: '|placeholder: '" | grep -v "Sheet"
```

Expected: no user-facing display strings remain (class names, comments, and the dashboard's `UpcomingChart` debug `toString()` are fine).

- [ ] **Step 3: Verify no test asserted the old copy, then run affected suites**

Run: `grep -rn "New Chart\|Delete Chart\|No charts\|Add chart\|'Charts'" test/`
Expected: no hits (if a hit appears, update that assertion to the new copy in this same commit).

Run: `flutter test test/features/library/ test/features/search/ test/features/band_settings/ 2>/dev/null || flutter test test/features/library/ test/features/search/`
Expected: PASS (`test/features/band_settings/` may not exist — skip it if absent).

- [ ] **Step 4: Commit**

```bash
git add lib/features/library lib/features/search lib/features/events lib/features/band_settings
git commit -m "feat(ui): relabel user-facing Chart copy as Sheet music

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 10: Full regression + PR

- [ ] **Step 1: Run the analyzer**

Run: `flutter analyze`
Expected: no errors, no new warnings.

- [ ] **Step 2: Run the full test suite**

Run: `flutter test`
Expected: all green. (Known gotcha from project memory: stale `.claude/worktrees` test copies can pollute runs — if unfamiliar failures appear from paths under `.claude/worktrees`, ignore/remove those copies.)

- [ ] **Step 3: Push and open the PR (target `main`)**

```bash
git push -u origin feat/song-list
gh pr create --base main --title "feat: song list management, segmented Library tab, sheet-music linking" --body "$(cat <<'EOF'
Implements the Flutter half of TTS/docs/superpowers/specs/2026-07-13-mobile-song-list-design.md:

- New lib/features/songs/ slice: unified Song model, Dio repository, AsyncNotifier with local create/update/delete, list/form/detail screens
- Library tab is now segmented: "Song list | Sheet music" (tab name/icon unchanged; Sheet music segment is the existing library screen unchanged)
- Song form: title/artist/key/genre/BPM (+ Look up via GET /api/mobile/songs/lookup)/notes/rating/energy steppers/lead singer (roster)/transition song/active
- Owner-only delete with confirmation (long-press, matching the library pattern)
- Chart create form + chart detail gain a Linked song picker (PATCH /api/mobile/bands/{band}/charts/{chart}); Chart model parses the new "song" block
- Operations screen gains a "Song list" NavRow (/songs)
- All user-facing "Chart(s)" copy relabeled "Sheet music" (identifiers/routes/permission keys unchanged)

Requires the backend PR from TTS feat/mobile-song-list (songs CRUD + lookup + chart PATCH endpoints).

Note: add/edit affordances are shown unconditionally (server enforces write:songs) because the app has no local per-resource permission signal — same as the existing charts library. Delete is additionally hidden for non-owners via BandSummary.isOwner.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Self-Review Notes (already applied)

- **Spec coverage (section 3 + relabel):** navigation/segmented tab (T4), Operations NavRow (T8), unified Song model (T1), constructor-injected repository (T2), AsyncNotifier watching `selectedBandProvider` + inactive filter (T3), list screen with search/refresh/filter/add (T4), form with full field parity incl. BPM lookup, roster lead-singer picker, transition picker, steppers, active toggle (T5), detail screen with Sheet music section (T6), owner-only delete with confirmation + long-press (T4), chart create/detail linking via the new PATCH + `song` block on `Chart` (T7), "Sheet music" relabel (T9), tests mirroring `test/features/library/**` throughout.
- **Deliberate deviation, flagged in Global Constraints and the PR body:** add/edit affordances are not hidden by `write:songs` because no such signal reaches the app (no ability decoding, no `can_write` in the songs payload); the library precedent shows them unconditionally. Owner-only delete IS gated locally via `BandSummary.isOwner`.
- **Type consistency spot-checks:** `SongsRepository.getSongs` returns the record `({List<Song> songs, List<String> genres})` everywhere (provider, fakes, tests); `SongFormScreen({this.existing})` matches both routes and the detail screen's push (`extra: song`); `updateChartSong(int, int, {required int? songId})` matches repository test and detail-screen call; `bandSongsProvider` is `FutureProvider.autoDispose.family<List<Song>, int>` in both T3 and T7 consumers; `leadSingerOptionsProvider` returns `List<RosterMember>` and the form maps picks into `SongLeadSinger`.
- **Ordering hazards addressed:** `/songs/new` registered before `/songs/:songId`; unused `library_screen.dart` import removed from the router in T4; `Chart.song` is an optional param so every existing `Chart(...)` construction (provider stamping, tests) compiles unchanged.
