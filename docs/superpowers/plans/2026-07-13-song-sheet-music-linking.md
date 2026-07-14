# Song-Side Sheet Music Linking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users link, unlink, and create sheet music (charts) from the song detail screen, not just from the chart side.

**Architecture:** Pure Flutter change (no backend work — `PATCH /bands/{band}/charts/{chart}` with `song_id` and `createChart(songId:)` already exist). A new `LibraryNotifier.updateChartSong` method owns the PATCH + state refresh; a new self-contained `SongSheetMusicSection` widget replaces the read-only section on `song_detail_screen.dart`; `CreateChartScreen` gains an optional `initialSong` for prefill via a new `CreateChartArgs` route extra.

**Tech Stack:** Flutter/Dart, Cupertino widgets, Riverpod v2 (`AsyncNotifier`), GoRouter, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-07-13-song-sheet-music-linking-design.md`

## Global Constraints

- Cupertino widgets only; match existing form/picker conventions in `chart_detail_screen.dart` and `song_form_screen.dart`.
- Dark-mode: use `context.primaryText` / `context.secondaryText` / `context.tertiaryText` from `core/theme/context_colors.dart`, never raw `CupertinoColors.secondaryLabel` in a `color:`.
- User-facing copy says "sheet music", never "chart".
- Error dialogs use `ErrorView.friendlyMessage(e)` in a `CupertinoAlertDialog` (matches `_LinkedSongEditor._showError`).
- This branch (`fix/song-singer-picker`) already carries the singer-picker fix commit `c005356`; the PR bundles both. Rename nothing.
- Run `flutter analyze` before every commit; the only pre-existing findings are 1 deprecation info in `secure_storage.dart` and 2 experimental warnings in `main.dart`.

---

### Task 1: `LibraryNotifier.updateChartSong`

**Files:**
- Modify: `lib/features/library/providers/library_provider.dart` (add method to `LibraryNotifier`, after `createChart`)
- Test: `test/features/library/providers/library_provider_test.dart`

**Interfaces:**
- Consumes: `LibraryRepository.updateChartSong(int bandId, int chartId, {required int? songId})` → `Future<Chart>` (exists, `lib/features/library/data/library_repository.dart:90`)
- Produces: `Future<void> updateChartSong(int bandId, int chartId, {required int? songId})` on `LibraryNotifier` — Task 3's section widget calls `ref.read(libraryProvider.notifier).updateChartSong(...)`.

- [ ] **Step 1: Write the failing tests**

Extend the existing `_FakeRepo` in `test/features/library/providers/library_provider_test.dart`:

```dart
// add fields to _FakeRepo:
  int? lastPatchedChartId;
  int? lastPatchedSongId;
  bool lastPatchHadSongId = false;

// add override to _FakeRepo:
  @override
  Future<Chart> updateChartSong(
    int bandId,
    int chartId, {
    required int? songId,
  }) async {
    lastPatchedChartId = chartId;
    lastPatchedSongId = songId;
    lastPatchHadSongId = true;
    final existing = charts.firstWhere((c) => c.id == chartId);
    return Chart(
      id: existing.id,
      bandId: existing.bandId,
      title: existing.title,
      composer: existing.composer,
      description: existing.description,
      price: existing.price,
      isPublic: existing.isPublic,
      uploadsCount: existing.uploadsCount,
      uploads: existing.uploads,
      band: null, // repo payload does not carry the stamped band
      song: songId != null
          ? ChartSongRef(id: songId, title: 'Linked Song')
          : null,
    );
  }
```

Add a test group (reuse the file's existing container/override style — `selectedBandProvider`, `songsRepositoryProvider` with `_FakeSongsRepo`, `libraryRepositoryProvider` with `_FakeRepo`):

```dart
group('updateChartSong', () {
  Chart chart(int id, {ChartSongRef? song}) => Chart(
        id: id,
        bandId: 1,
        title: 'Chart $id',
        composer: '',
        description: '',
        price: 0,
        isPublic: false,
        uploadsCount: 0,
        uploads: const [],
        band: const ChartBand(id: 1, name: 'Band', isPersonal: false),
        song: song,
      );

  test('links a song, patches local state, keeps the stamped band', () async {
    final repo = _FakeRepo(charts: [chart(11)]);
    final songsRepo = _FakeSongsRepo();
    final container = ProviderContainer(overrides: [
      libraryRepositoryProvider.overrideWithValue(repo),
      songsRepositoryProvider.overrideWithValue(songsRepo),
      selectedBandProvider.overrideWith(_StubBand.new),
    ]);
    addTearDown(container.dispose);
    await container.read(libraryProvider.future);

    await container
        .read(libraryProvider.notifier)
        .updateChartSong(1, 11, songId: 7);

    expect(repo.lastPatchedChartId, 11);
    expect(repo.lastPatchedSongId, 7);
    final state = container.read(libraryProvider).value!;
    final updated = state.charts.singleWhere((c) => c.id == 11);
    expect(updated.song?.id, 7);
    expect(updated.band?.name, 'Band',
        reason: 'local band stamp must survive the patch');
  });

  test('unlinks with songId null', () async {
    final repo = _FakeRepo(
        charts: [chart(11, song: const ChartSongRef(id: 7, title: 'S'))]);
    final container = ProviderContainer(overrides: [
      libraryRepositoryProvider.overrideWithValue(repo),
      songsRepositoryProvider.overrideWithValue(_FakeSongsRepo()),
      selectedBandProvider.overrideWith(_StubBand.new),
    ]);
    addTearDown(container.dispose);
    await container.read(libraryProvider.future);

    await container
        .read(libraryProvider.notifier)
        .updateChartSong(1, 11, songId: null);

    expect(repo.lastPatchHadSongId, true);
    expect(repo.lastPatchedSongId, isNull);
    final state = container.read(libraryProvider).value!;
    expect(state.charts.singleWhere((c) => c.id == 11).song, isNull);
  });

  test('invalidates songsProvider so song.charts refreshes', () async {
    final songsRepo = _FakeSongsRepo();
    final container = ProviderContainer(overrides: [
      libraryRepositoryProvider.overrideWithValue(_FakeRepo(charts: [chart(11)])),
      songsRepositoryProvider.overrideWithValue(songsRepo),
      selectedBandProvider.overrideWith(_StubBand.new),
    ]);
    addTearDown(container.dispose);
    await container.read(libraryProvider.future);
    await container.read(songsProvider.future);
    final callsBefore = songsRepo.getSongsCallCount;

    await container
        .read(libraryProvider.notifier)
        .updateChartSong(1, 11, songId: 7);
    await container.read(songsProvider.future);

    expect(songsRepo.getSongsCallCount, greaterThan(callsBefore));
  });
});
```

If the file has no `_StubBand`, add one matching `test/features/songs/screens/song_detail_screen_test.dart:10`:

```dart
class _StubBand extends SelectedBandNotifier {
  @override
  Future<int?> build() async => 1;
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/library/providers/library_provider_test.dart`
Expected: FAIL — `updateChartSong` isn't defined on `LibraryNotifier` (compile error).

- [ ] **Step 3: Implement the notifier method**

In `lib/features/library/providers/library_provider.dart`, after `createChart` (line ~108):

```dart
  /// Links ([songId] set) or unlinks ([songId] null) [chartId]'s song via the
  /// PATCH chart endpoint, patching the chart in local state. Preserves the
  /// locally stamped [Chart.band] (the PATCH payload does not carry it).
  Future<void> updateChartSong(
    int bandId,
    int chartId, {
    required int? songId,
  }) async {
    final repo = ref.read(libraryRepositoryProvider);
    final updated = await repo.updateChartSong(bandId, chartId, songId: songId);

    final current = state.value ?? const LibraryState();
    state = AsyncData(current.copyWith(charts: [
      for (final c in current.charts)
        if (c.id == chartId)
          Chart(
            id: c.id,
            bandId: c.bandId,
            title: c.title,
            composer: c.composer,
            description: c.description,
            price: c.price,
            isPublic: c.isPublic,
            uploadsCount: c.uploadsCount,
            uploads: c.uploads,
            band: c.band,
            song: updated.song,
          )
        else
          c,
    ]));

    // Linking/unlinking changes the affected songs' charts lists, which
    // songsProvider's cached list state doesn't know about.
    ref.invalidate(songsProvider);
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/library/providers/library_provider_test.dart`
Expected: PASS (all, including pre-existing).

- [ ] **Step 5: Commit**

```bash
git add lib/features/library/providers/library_provider.dart test/features/library/providers/library_provider_test.dart
git commit -m "feat(library): updateChartSong on LibraryNotifier with local state patch"
```

---

### Task 2: `CreateChartArgs` + prefill on `CreateChartScreen`

**Files:**
- Modify: `lib/features/library/screens/create_chart_screen.dart` (args class + `initialSong` param + `initState`)
- Modify: `lib/core/config/router.dart:499-504` (`/library/new` builder)
- Test: `test/features/library/screens/create_chart_screen_test.dart` (new file)

**Interfaces:**
- Consumes: `Song` (`lib/features/songs/data/models/song.dart` — fields `title`, `artist`), `BandSummary` (`lib/features/auth/data/models/band_summary.dart`).
- Produces: `class CreateChartArgs { const CreateChartArgs({required this.band, this.initialSong}); final BandSummary band; final Song? initialSong; }` exported from `create_chart_screen.dart`, and `CreateChartScreen({required BandSummary band, Song? initialSong})`. Task 3 pushes `context.push('/library/new', extra: CreateChartArgs(band: band, initialSong: song))`.

- [ ] **Step 1: Write the failing test**

Create `test/features/library/screens/create_chart_screen_test.dart`:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/library/screens/create_chart_screen.dart';
import 'package:tts_bandmate/features/songs/data/models/song.dart';

const _band = BandSummary(id: 2, name: 'The Testers', isOwner: true);

const _song = Song(
  id: 7,
  bandId: 2,
  title: 'September',
  artist: 'Earth, Wind & Fire',
  songKey: 'A',
  genre: 'Funk',
  bpm: 126,
  notes: '',
  active: true,
);

Widget _harness({Song? initialSong}) => ProviderScope(
      child: CupertinoApp(
        home: CreateChartScreen(band: _band, initialSong: initialSong),
      ),
    );

void main() {
  testWidgets('prefills title, composer, and linked song from initialSong',
      (tester) async {
    await tester.pumpWidget(_harness(initialSong: _song));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(CupertinoTextField, 'September'),
        findsOneWidget);
    expect(find.widgetWithText(CupertinoTextField, 'Earth, Wind & Fire'),
        findsOneWidget);
    // The linked-song row shows the preset song.
    expect(find.text('September'), findsWidgets);
  });

  testWidgets('without initialSong the form starts empty', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    expect(find.text('September'), findsNothing);
  });
}
```

(Adjust the `Song` const to the model's actual required params if the analyzer complains — `songKey`, `genre`, `bpm`, `notes` are required today.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/library/screens/create_chart_screen_test.dart`
Expected: FAIL — `initialSong` isn't a parameter (compile error).

- [ ] **Step 3: Implement prefill + args + router**

In `create_chart_screen.dart`:

```dart
/// Route extra for `/library/new`. [initialSong] pre-links the new chart and
/// prefills title/composer from the song.
class CreateChartArgs {
  const CreateChartArgs({required this.band, this.initialSong});
  final BandSummary band;
  final Song? initialSong;
}

class CreateChartScreen extends ConsumerStatefulWidget {
  const CreateChartScreen({super.key, required this.band, this.initialSong});

  final BandSummary band;
  final Song? initialSong;
  ...
```

Add `initState` to `_CreateChartScreenState`:

```dart
  @override
  void initState() {
    super.initState();
    final song = widget.initialSong;
    if (song != null) {
      _titleController.text = song.title;
      _composerController.text = song.artist;
      _linkedSong = song;
    }
  }
```

In `router.dart`, replace the `/library/new` builder (line ~499):

```dart
      GoRoute(
        path: '/library/new',
        builder: (_, state) {
          final extra = state.extra;
          if (extra is CreateChartArgs) {
            return CreateChartScreen(
              band: extra.band,
              initialSong: extra.initialSong,
            );
          }
          return CreateChartScreen(band: extra as BandSummary);
        },
      ),
```

(Import `CreateChartArgs` — same file as `CreateChartScreen`, already imported.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/library/screens/create_chart_screen_test.dart && flutter analyze`
Expected: PASS; analyze clean apart from the 3 pre-existing findings.

- [ ] **Step 5: Commit**

```bash
git add lib/features/library/screens/create_chart_screen.dart lib/core/config/router.dart test/features/library/screens/create_chart_screen_test.dart
git commit -m "feat(library): CreateChartArgs route extra prefills chart from a song"
```

---

### Task 3: `SongSheetMusicSection` widget

**Files:**
- Create: `lib/features/songs/widgets/song_sheet_music_section.dart`
- Modify: `lib/features/songs/screens/song_detail_screen.dart` (replace inline section lines 85-106; delete `_ChartRow` lines 235-285)
- Test: `test/features/songs/widgets/song_sheet_music_section_test.dart` (new file)

**Interfaces:**
- Consumes: `libraryProvider` / `LibraryNotifier.updateChartSong` (Task 1), `CreateChartArgs` (Task 2), `authProvider` (`AuthAuthenticated.bands`) to resolve the `BandSummary` for the create route, `Chart.song` (`ChartSongRef {id, title, artist}`).
- Produces: `SongSheetMusicSection({required Song song})` — a `ConsumerStatefulWidget` rendering the whole section including its `_SectionHeader`-equivalent header. `song_detail_screen.dart` embeds it in the `ListView`.

**Behavior spec (from the design doc):**
1. Header row: `SHEET MUSIC` label styled exactly like `_SectionHeader` in `song_detail_screen.dart:119-139`, with a trailing `Add` `CupertinoButton` (accessibility label `Add sheet music`). While a link/unlink call is in flight, the button is replaced by a `CupertinoActivityIndicator` and all actions are disabled (busy guard).
2. Body: same chart rows as today (icon, title, chevron, tap → `context.push('/library/${chart.id}', extra: song.bandId)`) plus a trailing ellipsis button (`CupertinoIcons.ellipsis`, accessibility label `Sheet music options for <title>`) that opens a `CupertinoActionSheet` with a destructive `Unlink sheet music` action and a `Cancel` button. Empty state keeps the existing copy `No sheet music linked to this song yet.`
3. Add flow: read the band's charts from `ref.read(libraryProvider.future)` filtered to `chart.bandId == song.bandId`, then `showCupertinoModalPopup` styled like `_showListPicker` in `song_form_screen.dart:433-482` with title `Sheet music`:
   - First row: `New sheet music…` → pop, resolve `BandSummary` from `authProvider` (`AuthAuthenticated.bands.firstWhere((b) => b.id == song.bandId)`; if absent, show the error dialog with message `Could not find this band's library.`), then `context.push('/library/new', extra: CreateChartArgs(band: band, initialSong: song))`.
   - Chart rows: title; when `chart.song != null && chart.song!.id != song.id`, a secondary line `Linked to <chart.song!.title>` in `context.secondaryText` fontSize 12; when `chart.song?.id == song.id` the row is disabled (onPressed null, `context.tertiaryText` title) with a trailing `checkmark` icon.
   - Picking an unlinked chart → `updateChartSong(song.bandId, chart.id, songId: song.id)`.
   - Picking a chart linked elsewhere → `CupertinoAlertDialog` title `Move Sheet Music?`, content `"<chart title>" is linked to "<other song title>". Move it to "<this song title>"?`, actions `Cancel` / destructive `Move`. Only `Move` PATCHes.
4. Unlink flow: action sheet's `Unlink sheet music` → `updateChartSong(song.bandId, chart.id, songId: null)`.
5. Errors from the charts fetch or any PATCH: `CupertinoAlertDialog` title `Could Not Update Link`, content `ErrorView.friendlyMessage(e)`, single `OK` action (copy matches `chart_detail_screen.dart:1040-1053`). Busy state always cleared in `finally`.

- [ ] **Step 1: Write the failing tests**

Create `test/features/songs/widgets/song_sheet_music_section_test.dart`. Harness pattern: combine the fakes from `test/features/songs/screens/song_detail_screen_test.dart` (StubBand, `_FakeRepo` for songs) with `library_screen_test.dart`'s (`_StubAuthNotifier`, fake `LibraryRepository`), and a `GoRouter` with `/` (a `CupertinoPageScaffold` with `ListView(children: [SongSheetMusicSection(song: _song)])`), `/library/new` and `/library/:chartId` capture routes.

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/auth/data/models/auth_user.dart';
import 'package:tts_bandmate/features/auth/providers/auth_provider.dart';
import 'package:tts_bandmate/features/library/data/library_repository.dart';
import 'package:tts_bandmate/features/library/data/models/chart.dart';
import 'package:tts_bandmate/features/library/screens/create_chart_screen.dart';
import 'package:tts_bandmate/features/songs/data/models/song.dart';
import 'package:tts_bandmate/features/songs/data/songs_repository.dart';
import 'package:tts_bandmate/features/songs/widgets/song_sheet_music_section.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';

// _StubBand / _FakeSongsRepo: copy from song_detail_screen_test.dart.
// _StubAuthNotifier + AuthUser const: copy from library_screen_test.dart
// (const _user = AuthUser(id: 1, name: 'Eddie', email: 'e@e.com', avatarUrl: null)).

class _FakeLibraryRepo implements LibraryRepository {
  _FakeLibraryRepo(this.charts, {this.failPatch = false});
  final List<Chart> charts;
  final bool failPatch;
  int? lastPatchedChartId;
  int? lastPatchedSongId;
  bool patchCalled = false;

  @override
  Future<List<Chart>> getAllCharts() async => charts;

  @override
  Future<Chart> updateChartSong(int bandId, int chartId,
      {required int? songId}) async {
    if (failPatch) throw Exception('nope');
    patchCalled = true;
    lastPatchedChartId = chartId;
    lastPatchedSongId = songId;
    final c = charts.firstWhere((c) => c.id == chartId);
    return Chart(
      id: c.id, bandId: c.bandId, title: c.title, composer: c.composer,
      description: c.description, price: c.price, isPublic: c.isPublic,
      uploadsCount: c.uploadsCount, uploads: c.uploads,
      song: songId == null ? null : ChartSongRef(id: songId, title: 'x'),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
```

Test cases (write all of them; each pumps the harness, `pumpAndSettle`, acts, asserts):

```dart
testWidgets('Add opens the picker listing the band charts with link status', ...);
// taps 'Add sheet music', expects picker rows: 'New sheet music…',
// unlinked chart title, and 'Linked to Other Song' subtitle on the taken one;
// chart already linked to THIS song rendered disabled with a checkmark.

testWidgets('picking an unlinked chart PATCHes song_id', ...);
// tap chart row → repo.lastPatchedChartId == chart.id,
// repo.lastPatchedSongId == song.id.

testWidgets('picking a chart linked elsewhere confirms before moving', ...);
// tap taken chart → 'Move Sheet Music?' dialog; tap Cancel → patchCalled
// is false; reopen, tap Move → patch issued.

testWidgets('unlink action sheet PATCHes song_id null', ...);
// tap ellipsis on linked row → 'Unlink sheet music' → lastPatchedSongId null.

testWidgets('New sheet music routes to /library/new with CreateChartArgs', ...);
// tap 'New sheet music…' → captured extra is CreateChartArgs with
// band.id == song.bandId and initialSong?.id == song.id.

testWidgets('PATCH failure shows Could Not Update Link and re-enables Add', ...);
// failPatch: true → dialog appears; dismiss OK; 'Add sheet music' button
// (not the spinner) is visible again.
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/songs/widgets/song_sheet_music_section_test.dart`
Expected: FAIL — `song_sheet_music_section.dart` doesn't exist (compile error).

- [ ] **Step 3: Implement the widget**

Create `lib/features/songs/widgets/song_sheet_music_section.dart` implementing the behavior spec above. Skeleton:

```dart
class SongSheetMusicSection extends ConsumerStatefulWidget {
  const SongSheetMusicSection({super.key, required this.song});
  final Song song;
  @override
  ConsumerState<SongSheetMusicSection> createState() =>
      _SongSheetMusicSectionState();
}

class _SongSheetMusicSectionState
    extends ConsumerState<SongSheetMusicSection> {
  bool _busy = false;

  Future<void> _patch(int chartId, int? songId) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(libraryProvider.notifier)
          .updateChartSong(widget.song.bandId, chartId, songId: songId);
    } catch (e) {
      if (mounted) _showError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
  ...
}
```

Keep every sub-widget private to this file (`_HeaderRow`, `_LinkedChartRow`, `_ChartPickerSheet` rows). Reuse the visual constants from the code being replaced (`song_detail_screen.dart:235-285`) verbatim for the row look.

In `song_detail_screen.dart`, replace lines 85-106 with:

```dart
                    SongSheetMusicSection(song: song),
```

Delete `_ChartRow` (lines 235-285) and the now-unused import if any. `_SongDetailBody` stays a `StatelessWidget`; the section brings its own `ConsumerStatefulWidget`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/songs/ && flutter analyze`
Expected: PASS including the existing `song_detail_screen_test.dart` (its `SHEET MUSIC` header, chart-row tap, and copy assertions must still hold — the section reproduces them).

- [ ] **Step 5: Commit**

```bash
git add lib/features/songs/widgets/song_sheet_music_section.dart lib/features/songs/screens/song_detail_screen.dart test/features/songs/widgets/song_sheet_music_section_test.dart
git commit -m "feat(songs): manage sheet music links from the song detail screen"
```

---

### Task 4: Full verification + PR

**Files:** none new.

- [ ] **Step 1: Full suite + analyzer**

Run: `flutter analyze && flutter test`
Expected: analyze shows only the 3 pre-existing findings; all tests pass (1004+ before this work).

- [ ] **Step 2: On-device verification (verify skill / run-on-device)**

Drive the real flow on the phone against the local backend: song detail → Add sheet music → link an unlinked chart; relink a taken one (confirm dialog); unlink; New sheet music → confirm title/composer/link prefilled; save and check the chart appears under the song. Also re-check the original bug: song edit → Lead singer → names render.

- [ ] **Step 3: Version bump check**

If `gh pr list --state open` shows an open release-please PR, bump `pubspec.yaml` version in this branch (memory: feedback_manual_version_bump).

- [ ] **Step 4: Push and open the PR (base `main`)**

```bash
git push -u origin fix/song-singer-picker
gh pr create --base main \
  --title "feat: song-side sheet music linking + fix blank singer picker names" \
  --body "$(cat <<'EOF'
## Summary
- fix(personnel): lead-singer picker showed blank rows — raw roster payloads carry the name in `display_name`, not `name`, for user-linked members
- feat(songs): manage sheet music from the song detail screen — link existing charts (with move confirmation when taken), unlink, and create a new chart prefilled with the song's title/artist and pre-linked

Spec: docs/superpowers/specs/2026-07-13-song-sheet-music-linking-design.md

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 5: Wait for Copilot review and address comments**

Memory: feedback_wait_for_copilot_pr_review — poll `gh pr view --comments` until Copilot's review lands; address findings before calling the PR done.
