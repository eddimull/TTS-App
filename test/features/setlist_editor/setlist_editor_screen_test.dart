import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show DefaultMaterialLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/setlist_editor/data/models/event_setlist.dart';
import 'package:tts_bandmate/features/setlist_editor/data/setlist_editor_repository.dart';
import 'package:tts_bandmate/features/setlist_editor/providers/setlist_editor_provider.dart';
import 'package:tts_bandmate/features/setlist_editor/screens/setlist_editor_screen.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';

// ── Fake repository ────────────────────────────────────────────────────────────

class _FakeRepo extends SetlistEditorRepository {
  _FakeRepo(this._payload) : super(Dio());

  final SetlistEditorPayload _payload;

  int saveCalls = 0;
  String? lastSavedStatus;

  @override
  Future<SetlistEditorPayload> getSetlist(String eventKey) async => _payload;

  @override
  Future<EventSetlist> updateSetlist(
    String eventKey,
    List<SetlistEntry> entries, {
    String? status,
  }) async {
    saveCalls++;
    lastSavedStatus = status;
    return EventSetlist(
      id: _payload.setlist?.id ?? 1,
      status: status ?? _payload.setlist?.status ?? 'draft',
      songs: entries,
    );
  }

  @override
  Future<EventSetlist> generate(String eventKey, {String? context}) async {
    return const EventSetlist(
      id: 1,
      status: 'draft',
      songs: [
        SetlistEntry(type: 'song', position: 1, songId: 99, title: 'Generated Song'),
      ],
    );
  }

  @override
  Future<RefineResult> refine(
    String eventKey, {
    required String message,
    List<Map<String, String>> history = const [],
  }) async {
    return const RefineResult(
      setlist: EventSetlist(id: 1, status: 'draft', songs: []),
      summary: 'Done.',
    );
  }
}

// ── Test helpers ───────────────────────────────────────────────────────────────

/// Wraps the screen in a ProviderScope with a fake repo override and an
/// optional [bandId] override for [selectedBandProvider].
///
/// Includes both Cupertino and Material localizations so that
/// [ReorderableListView] (Material widget used inside the screen) does not
/// throw a "No MaterialLocalizations found" assertion.
Widget _app(
  Widget screen, {
  required _FakeRepo repo,
  int? bandId = 1,
}) {
  return ProviderScope(
    overrides: [
      setlistEditorRepositoryProvider.overrideWithValue(repo),
      // Override selectedBandProvider to return the given bandId without
      // hitting secure storage.
      selectedBandProvider.overrideWith(() => _FakeBandNotifier(bandId)),
    ],
    child: CupertinoApp(
      // CupertinoApp does not include Material localizations by default.
      // ReorderableListView requires MaterialLocalizations, so we inject them
      // here via localizationsDelegates.
      localizationsDelegates: const [
        DefaultMaterialLocalizations.delegate,
        DefaultCupertinoLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],
      home: screen,
    ),
  );
}

/// Fake SelectedBandNotifier that resolves immediately with a fixed value.
class _FakeBandNotifier extends SelectedBandNotifier {
  _FakeBandNotifier(this._id);
  final int? _id;

  @override
  Future<int?> build() async => _id;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  const eventKey = 'test-event-key';

  // ── (1) Loading shows spinner ────────────────────────────────────────────────

  testWidgets('shows CupertinoActivityIndicator during initial load',
      (tester) async {
    // Build a fake repo whose getSetlist never completes so we can catch the
    // loading frame.
    final slowRepo = _SlowRepo();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          setlistEditorRepositoryProvider.overrideWithValue(slowRepo),
          selectedBandProvider.overrideWith(() => _FakeBandNotifier(1)),
        ],
        child: const CupertinoApp(
          localizationsDelegates: [
            DefaultMaterialLocalizations.delegate,
            DefaultCupertinoLocalizations.delegate,
            DefaultWidgetsLocalizations.delegate,
          ],
          home: SetlistEditorScreen(eventKey: eventKey),
        ),
      ),
    );

    // The screen starts with isLoading:true (notifier build default) and then
    // the postFrame callback fires load(). Pump once to trigger the frame.
    await tester.pump();

    // Before the slow load resolves the spinner should be visible.
    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
  });

  // ── (2) Empty state shows 'No setlist yet' ───────────────────────────────────

  testWidgets('loaded empty state shows No setlist yet', (tester) async {
    final repo = _FakeRepo(const SetlistEditorPayload(
      setlist: EventSetlist(id: 1, status: 'draft', songs: []),
      bandSongs: [],
      canWrite: true,
    ));

    await tester.pumpWidget(_app(
      const SetlistEditorScreen(eventKey: eventKey),
      repo: repo,
    ));

    await tester.pumpAndSettle();

    expect(find.text('No setlist yet'), findsOneWidget);
    expect(find.text('Add songs manually or generate one with AI.'),
        findsOneWidget);
  });

  // ── (3) Rows render + status bar shows song count ────────────────────────────

  testWidgets('loaded setlist renders one row per song and correct song count',
      (tester) async {
    final repo = _FakeRepo(const SetlistEditorPayload(
      setlist: EventSetlist(
        id: 1,
        status: 'draft',
        songs: [
          SetlistEntry(type: 'song', position: 1, songId: 10, title: 'Alpha'),
          SetlistEntry(type: 'song', position: 2, songId: 11, title: 'Beta'),
          SetlistEntry(type: 'break', position: 3),
        ],
      ),
      bandSongs: [],
      canWrite: true,
    ));

    await tester.pumpWidget(_app(
      const SetlistEditorScreen(eventKey: eventKey),
      repo: repo,
    ));

    await tester.pumpAndSettle();

    // Song titles should be visible.
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);

    // Status bar counts non-break entries only: 2 songs, 1 break → '2 songs'.
    expect(find.text('2 songs'), findsOneWidget);

    // Break row label.
    expect(find.text('— SET BREAK —'), findsOneWidget);
  });

  // ── (4) Read-only hides toolbar + Save button ────────────────────────────────

  testWidgets('read-only mode hides bottom toolbar and Save button',
      (tester) async {
    final repo = _FakeRepo(const SetlistEditorPayload(
      setlist: EventSetlist(
        id: 1,
        status: 'draft',
        songs: [
          SetlistEntry(type: 'song', position: 1, songId: 10, title: 'Alpha'),
        ],
      ),
      bandSongs: [],
      canWrite: false, // <-- read-only
    ));

    await tester.pumpWidget(_app(
      const SetlistEditorScreen(eventKey: eventKey),
      repo: repo,
    ));

    await tester.pumpAndSettle();

    // No "Song" / "Break" / "Generate" / "Refine" labels in the toolbar.
    expect(find.text('Song'), findsNothing);
    expect(find.text('Break'), findsNothing);
    expect(find.text('Generate'), findsNothing);
    expect(find.text('Refine'), findsNothing);

    // No "Save" text in the nav bar.
    expect(find.text('Save'), findsNothing);
  });

  // ── (5) Save fires on tap when dirty ─────────────────────────────────────────

  testWidgets('Save button is present when dirty and calls save on tap',
      (tester) async {
    final repo = _FakeRepo(const SetlistEditorPayload(
      setlist: EventSetlist(id: 1, status: 'draft', songs: []),
      bandSongs: [BandSongSummary(id: 10, title: 'A')],
      canWrite: true,
    ));

    await tester.pumpWidget(_app(
      const SetlistEditorScreen(eventKey: eventKey),
      repo: repo,
    ));

    await tester.pumpAndSettle();

    // Manually mark dirty by adding a song through the notifier — we access it
    // via the ProviderContainer embedded in the ProviderScope.
    // Instead, find the ProviderScope container and drive the notifier directly.
    final element = tester.element(find.byType(SetlistEditorScreen));
    final container = ProviderScope.containerOf(element);

    // Pre-load data so we can dirty the state.
    container.read(setlistEditorProvider(eventKey).notifier).addBreak();

    await tester.pump();

    // Now Save should be enabled (isDirty = true).
    final saveFinder = find.text('Save');
    expect(saveFinder, findsOneWidget);

    await tester.tap(saveFinder);
    await tester.pumpAndSettle();

    expect(repo.saveCalls, equals(1));
  });

  // ── (6) Generate button is gated on bandId ───────────────────────────────────

  testWidgets('Generate button disabled when selectedBandProvider has no band',
      (tester) async {
    final repo = _FakeRepo(const SetlistEditorPayload(
      setlist: EventSetlist(id: 1, status: 'draft', songs: []),
      bandSongs: [],
      canWrite: true,
    ));

    await tester.pumpWidget(_app(
      const SetlistEditorScreen(eventKey: eventKey),
      repo: repo,
      bandId: null, // <-- no band selected
    ));

    await tester.pumpAndSettle();

    // The Generate button exists but should be disabled (onPressed == null).
    // We confirm by checking that tapping it does NOT open the generate sheet
    // (sheet would show a 'Generate' header text above the button label).
    await tester.tap(find.text('Generate'));
    await tester.pumpAndSettle();

    // No generate sheet dialog opened.
    expect(find.text('Generate Setlist'), findsNothing);
  });
}

// ── Helpers ───────────────────────────────────────────────────────────────────

/// A repo whose [getSetlist] never resolves — lets tests observe the loading
/// state before data arrives.
class _SlowRepo extends SetlistEditorRepository {
  _SlowRepo() : super(Dio());

  @override
  Future<SetlistEditorPayload> getSetlist(String eventKey) =>
      Completer<SetlistEditorPayload>().future; // never completes
}
