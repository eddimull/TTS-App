import 'dart:async';

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
import 'package:tts_bandmate/features/songs/widgets/song_sheet_music_section.dart';

const _user = AuthUser(id: 1, name: 'Eddie', email: 'e@e.com', avatarUrl: null);
const _band = BandSummary(id: 2, name: 'The Band', isOwner: true);

const _song = Song(
  id: 7,
  bandId: 2,
  title: 'September',
  artist: 'Earth, Wind & Fire',
  charts: [SongChartSummary(id: 11, title: 'September - Horns')],
);

class _StubAuthNotifier extends AuthNotifier {
  _StubAuthNotifier(this._bands);
  final List<BandSummary> _bands;
  @override
  Future<AuthState> build() async =>
      AuthAuthenticated(user: _user, bands: _bands);
}

class _FakeLibraryRepo implements LibraryRepository {
  _FakeLibraryRepo(this.charts, {this.failPatch = false, this.pendingPatch});
  final List<Chart> charts;
  final bool failPatch;
  /// When set, `updateChartSong` doesn't resolve until this completer does —
  /// lets a test hold a PATCH "in flight" to exercise the busy guard.
  final Completer<void>? pendingPatch;
  int? lastPatchedChartId;
  int? lastPatchedSongId;
  bool patchCalled = false;
  int patchCallCount = 0;

  @override
  Future<List<Chart>> getAllCharts() async => charts;

  @override
  Future<Chart> updateChartSong(int bandId, int chartId,
      {required int? songId}) async {
    if (pendingPatch != null) await pendingPatch!.future;
    if (failPatch) throw Exception('nope');
    patchCalled = true;
    patchCallCount++;
    lastPatchedChartId = chartId;
    lastPatchedSongId = songId;
    final c = charts.firstWhere((c) => c.id == chartId);
    return Chart(
      id: c.id,
      bandId: c.bandId,
      title: c.title,
      composer: c.composer,
      description: c.description,
      price: c.price,
      isPublic: c.isPublic,
      uploadsCount: c.uploadsCount,
      uploads: c.uploads,
      song: songId == null ? null : ChartSongRef(id: songId, title: 'x'),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Chart _chart({
  required int id,
  required String title,
  ChartSongRef? song,
}) =>
    Chart(
      id: id,
      bandId: _song.bandId,
      title: title,
      composer: '',
      description: '',
      price: 0,
      isPublic: false,
      uploadsCount: 0,
      uploads: const [],
      song: song,
    );

String? pushedLocation;
Object? pushedExtra;

Widget _harness({
  required List<Chart> charts,
  List<BandSummary>? bands,
  bool failPatch = false,
  _FakeLibraryRepo? repoOverride,
}) {
  final repo = repoOverride ?? _FakeLibraryRepo(charts, failPatch: failPatch);
  final router = GoRouter(routes: [
    GoRoute(
      path: '/',
      builder: (_, __) => CupertinoPageScaffold(
        child: SafeArea(
          child: ListView(children: const [SongSheetMusicSection(song: _song)]),
        ),
      ),
    ),
    GoRoute(
      path: '/library/new',
      builder: (_, state) {
        pushedLocation = state.uri.path;
        pushedExtra = state.extra;
        return const CupertinoPageScaffold(child: Text('create chart'));
      },
    ),
    GoRoute(
      path: '/library/:chartId',
      builder: (_, state) {
        pushedLocation = state.uri.path;
        pushedExtra = state.extra;
        return const CupertinoPageScaffold(child: Text('chart detail'));
      },
    ),
  ]);
  return ProviderScope(
    overrides: [
      authProvider.overrideWith(() => _StubAuthNotifier(bands ?? [_band])),
      libraryRepositoryProvider.overrideWithValue(repo),
    ],
    child: CupertinoApp.router(routerConfig: router),
  );
}

_FakeLibraryRepo _repoOf(WidgetTester tester) {
  final element = tester.element(find.byType(SongSheetMusicSection));
  final container = ProviderScope.containerOf(element);
  return container.read(libraryRepositoryProvider) as _FakeLibraryRepo;
}

/// Bounded alternative to `pumpAndSettle()` for use once a flow is holding
/// the busy guard: the header's `CupertinoActivityIndicator` animates
/// forever while `_busy` is true (by design — see the busy-guard fix), so
/// `pumpAndSettle()` would time out. This just pumps enough frames for a
/// modal-popup/dialog route transition to finish opening.
Future<void> _settleModal(WidgetTester tester) async {
  await tester.pump();
  // 350ms clears the Cupertino modal-popup transition (335ms) with margin.
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  setUp(() {
    pushedLocation = null;
    pushedExtra = null;
  });

  testWidgets(
      'Add opens the picker listing the band charts with link status',
      (tester) async {
    final charts = [
      _chart(id: 11, title: 'September - Horns', song: const ChartSongRef(id: 7, title: 'September')),
      _chart(id: 12, title: 'Unlinked Chart'),
      _chart(id: 13, title: 'Taken Chart', song: const ChartSongRef(id: 99, title: 'Other Song')),
    ];

    await tester.pumpWidget(_harness(charts: charts));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Add sheet music'));
    await _settleModal(tester);

    expect(find.text('New sheet music…'), findsOneWidget);
    expect(find.text('Unlinked Chart'), findsOneWidget);
    expect(find.text('Taken Chart'), findsOneWidget);
    expect(find.text('Linked to Other Song'), findsOneWidget);

    // The chart already linked to THIS song (September - Horns → song 7)
    // appears disabled with a checkmark, inside the picker sheet. Find the
    // CupertinoButton ancestor of the checkmark icon (unique in the tree)
    // and confirm it wraps the "September - Horns" text and is disabled.
    final checkmarkFinder = find.byIcon(CupertinoIcons.checkmark);
    expect(checkmarkFinder, findsOneWidget);
    final linkedRowFinder = find.ancestor(
      of: checkmarkFinder,
      matching: find.byType(CupertinoButton),
    );
    expect(
      find.descendant(
        of: linkedRowFinder,
        matching: find.text('September - Horns'),
      ),
      findsOneWidget,
    );
    final linkedRow = tester.widget<CupertinoButton>(linkedRowFinder);
    expect(linkedRow.onPressed, isNull);
  });

  testWidgets('picking an unlinked chart PATCHes song_id', (tester) async {
    final charts = [
      _chart(id: 11, title: 'September - Horns', song: const ChartSongRef(id: 7, title: 'September')),
      _chart(id: 12, title: 'Unlinked Chart'),
    ];

    await tester.pumpWidget(_harness(charts: charts));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Add sheet music'));
    await _settleModal(tester);

    await tester.tap(find.text('Unlinked Chart'));
    await tester.pumpAndSettle();

    final repo = _repoOf(tester);
    expect(repo.lastPatchedChartId, 12);
    expect(repo.lastPatchedSongId, 7);
  });

  testWidgets('picking a chart linked elsewhere confirms before moving',
      (tester) async {
    final charts = [
      _chart(id: 11, title: 'September - Horns', song: const ChartSongRef(id: 7, title: 'September')),
      _chart(id: 13, title: 'Taken Chart', song: const ChartSongRef(id: 99, title: 'Other Song')),
    ];

    await tester.pumpWidget(_harness(charts: charts));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Add sheet music'));
    await _settleModal(tester);

    await tester.tap(find.text('Taken Chart'));
    await _settleModal(tester);

    expect(find.text('Move Sheet Music?'), findsOneWidget);
    expect(
      find.text(
        '"Taken Chart" is linked to "Other Song". Move it to "September"?',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    var repo = _repoOf(tester);
    expect(repo.patchCalled, isFalse);

    // Reopen and tap Move.
    await tester.tap(find.bySemanticsLabel('Add sheet music'));
    await _settleModal(tester);
    await tester.tap(find.text('Taken Chart'));
    await _settleModal(tester);
    await tester.tap(find.text('Move'));
    await tester.pumpAndSettle();

    repo = _repoOf(tester);
    expect(repo.patchCalled, isTrue);
    expect(repo.lastPatchedChartId, 13);
    expect(repo.lastPatchedSongId, 7);
  });

  testWidgets('unlink action sheet PATCHes song_id null', (tester) async {
    final charts = [
      _chart(id: 11, title: 'September - Horns', song: const ChartSongRef(id: 7, title: 'September')),
    ];

    await tester.pumpWidget(_harness(charts: charts));
    await tester.pumpAndSettle();

    await tester.tap(
      find.bySemanticsLabel('Sheet music options for September - Horns'),
    );
    await _settleModal(tester);

    expect(find.text('Unlink sheet music'), findsOneWidget);
    await tester.tap(find.text('Unlink sheet music'));
    await tester.pumpAndSettle();

    final repo = _repoOf(tester);
    expect(repo.lastPatchedChartId, 11);
    expect(repo.lastPatchedSongId, isNull);
  });

  testWidgets('New sheet music routes to /library/new with CreateChartArgs',
      (tester) async {
    final charts = [
      _chart(id: 11, title: 'September - Horns', song: const ChartSongRef(id: 7, title: 'September')),
    ];

    await tester.pumpWidget(_harness(charts: charts));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Add sheet music'));
    await _settleModal(tester);

    await tester.tap(find.text('New sheet music…'));
    await tester.pumpAndSettle();

    expect(pushedLocation, '/library/new');
    final extra = pushedExtra;
    expect(extra, isA<CreateChartArgs>());
    final args = extra as CreateChartArgs;
    expect(args.band.id, _song.bandId);
    expect(args.initialSong?.id, _song.id);
  });

  testWidgets('PATCH failure shows Could Not Update Link and re-enables Add',
      (tester) async {
    final charts = [
      _chart(id: 11, title: 'September - Horns', song: const ChartSongRef(id: 7, title: 'September')),
      _chart(id: 12, title: 'Unlinked Chart'),
    ];

    await tester.pumpWidget(_harness(charts: charts, failPatch: true));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Add sheet music'));
    await _settleModal(tester);

    await tester.tap(find.text('Unlinked Chart'));
    await tester.pumpAndSettle();

    expect(find.text('Could Not Update Link'), findsOneWidget);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Add sheet music'), findsOneWidget);
    expect(find.byType(CupertinoActivityIndicator), findsNothing);
  });

  testWidgets(
      'busy guard blocks reentry while a PATCH is in flight, and '
      're-enables once it completes', (tester) async {
    final charts = [
      _chart(id: 11, title: 'September - Horns',
          song: const ChartSongRef(id: 7, title: 'September')),
      _chart(id: 12, title: 'Unlinked Chart'),
    ];
    final pendingPatch = Completer<void>();
    final repo = _FakeLibraryRepo(charts, pendingPatch: pendingPatch);

    await tester.pumpWidget(_harness(charts: charts, repoOverride: repo));
    await tester.pumpAndSettle();

    // Start the Add flow and pick an unlinked chart — this issues the PATCH,
    // which now blocks on `pendingPatch`, holding `_busy` true across the
    // whole flow (picker already dismissed itself via Navigator.pop, but the
    // flow's finally hasn't run yet).
    await tester.tap(find.bySemanticsLabel('Add sheet music'));
    await _settleModal(tester);
    await tester.tap(find.text('Unlinked Chart'));
    await _settleModal(tester);

    // Header shows the spinner instead of the Add button while the PATCH is
    // in flight.
    expect(find.bySemanticsLabel('Add sheet music'), findsNothing);
    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);

    // Row actions are disabled: tapping the ellipsis (or the row) does
    // nothing — no second repo call is issued.
    await tester.tap(
      find.bySemanticsLabel('Sheet music options for September - Horns'),
    );
    await tester.pump();
    expect(find.text('Unlink sheet music'), findsNothing);
    expect(repo.patchCallCount, 0);

    // Complete the in-flight PATCH and let the flow's finally clear _busy.
    pendingPatch.complete();
    await tester.pumpAndSettle();

    expect(repo.patchCallCount, 1);
    expect(repo.lastPatchedChartId, 12);
    expect(repo.lastPatchedSongId, 7);
    expect(find.bySemanticsLabel('Add sheet music'), findsOneWidget);
    expect(find.byType(CupertinoActivityIndicator), findsNothing);
  });
}
