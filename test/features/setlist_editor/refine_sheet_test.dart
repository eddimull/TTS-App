import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/setlist_editor/data/models/event_setlist.dart';
import 'package:tts_bandmate/features/setlist_editor/data/setlist_editor_repository.dart';
import 'package:tts_bandmate/features/setlist_editor/widgets/refine_sheet.dart';

// ---------------------------------------------------------------------------
// Fake repository
// ---------------------------------------------------------------------------

/// Controls the outcome of a single [refine] call.
class _FakeRefineControl {
  _FakeRefineControl({required this.summary, this.throws = false});
  final String summary;
  final bool throws;

  // If non-null, [refine] suspends until this completer completes.
  Completer<RefineResult>? completer;
}

class _FakeRepo extends SetlistEditorRepository {
  _FakeRepo() : super(Dio());

  // Queue of controls consumed in FIFO order by [refine] calls.
  final List<_FakeRefineControl> _controls = [];

  // Captured arguments from [refine] calls (all accumulated).
  final List<Map<String, dynamic>> refineCalls = [];

  void enqueue(_FakeRefineControl ctrl) => _controls.add(ctrl);

  @override
  Future<SetlistEditorPayload> getSetlist(String eventKey) async =>
      const SetlistEditorPayload(setlist: null, bandSongs: [], canWrite: true);

  @override
  Future<EventSetlist> updateSetlist(
    String eventKey,
    List<SetlistEntry> entries, {
    String? status,
  }) async =>
      const EventSetlist(id: 1, status: 'draft', songs: []);

  @override
  Future<EventSetlist> generate(String eventKey, {String? context}) async =>
      const EventSetlist(id: 1, status: 'draft', songs: []);

  @override
  Future<RefineResult> refine(
    String eventKey, {
    required String message,
    List<Map<String, String>> history = const [],
  }) async {
    refineCalls.add({'message': message, 'history': history});

    final ctrl = _controls.removeAt(0);

    // If the control has a completer, suspend until it's resolved externally.
    if (ctrl.completer != null) {
      return ctrl.completer!.future;
    }

    if (ctrl.throws) throw Exception('network error');

    return RefineResult(
      setlist: const EventSetlist(
        id: 1,
        status: 'draft',
        songs: [
          SetlistEntry(type: 'song', position: 1, songId: 1, title: 'Refined'),
        ],
      ),
      summary: ctrl.summary,
    );
  }
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

const _eventKey = 'evt-test-001';

/// Pumps a CupertinoApp that opens [_RefineSheet] via [showRefineSheet].
/// Tapping the 'Open Sheet' button triggers the popup.
Future<_FakeRepo> _pumpSheetHost(WidgetTester tester) async {
  final repo = _FakeRepo();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        setlistEditorRepositoryProvider.overrideWithValue(repo),
      ],
      child: CupertinoApp(
        home: Builder(
          builder: (context) => CupertinoPageScaffold(
            child: Center(
              child: CupertinoButton(
                onPressed: () => showRefineSheet(context, eventKey: _eventKey),
                child: const Text('Open Sheet'),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  // Open the sheet.
  await tester.tap(find.text('Open Sheet'));
  await tester.pumpAndSettle();

  return repo;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('RefineSheet — chat flow', () {
    testWidgets(
        'typing a message and tapping send appends user bubble then assistant bubble',
        (tester) async {
      final repo = await _pumpSheetHost(tester);
      repo.enqueue(_FakeRefineControl(summary: 'Done! Swapped song 2.'));

      // The empty-state hint should be visible before any message.
      expect(find.textContaining('Describe what you\'d like to change'), findsOneWidget);

      // Enter a message.
      await tester.enterText(
          find.byType(CupertinoTextField), 'Swap song 2 for something slower');
      await tester.pump();

      // Tap the send button (arrow_up_circle_fill icon).
      await tester.tap(find.byIcon(CupertinoIcons.arrow_up_circle_fill));
      // Pump to let setState append user bubble.
      await tester.pump();

      // User bubble should appear immediately.
      expect(find.text('Swap song 2 for something slower'), findsOneWidget);

      // The text field should be cleared.
      expect(
        tester
            .widget<CupertinoTextField>(find.byType(CupertinoTextField))
            .controller!
            .text,
        isEmpty,
      );

      // Settle the async refine call.
      await tester.pumpAndSettle();

      // Assistant reply bubble should now appear.
      expect(find.text('Done! Swapped song 2.'), findsOneWidget);

      // Verify the repo was called.
      expect(repo.refineCalls, hasLength(1));
      expect(repo.refineCalls.first['message'], 'Swap song 2 for something slower');
    });

    testWidgets(
        'history passed to refine accumulates prior turns',
        (tester) async {
      final repo = await _pumpSheetHost(tester);
      repo.enqueue(_FakeRefineControl(summary: 'Turn 1 done.'));
      repo.enqueue(_FakeRefineControl(summary: 'Turn 2 done.'));

      // ── First message ──────────────────────────────────────────────────────
      await tester.enterText(find.byType(CupertinoTextField), 'First request');
      await tester.pump();
      await tester.tap(find.byIcon(CupertinoIcons.arrow_up_circle_fill));
      await tester.pumpAndSettle();

      // First call should have an empty history (no prior turns).
      expect(repo.refineCalls.first['history'], isEmpty);

      // ── Second message ─────────────────────────────────────────────────────
      await tester.enterText(find.byType(CupertinoTextField), 'Second request');
      await tester.pump();
      await tester.tap(find.byIcon(CupertinoIcons.arrow_up_circle_fill));
      await tester.pumpAndSettle();

      // Second call should carry the two turns from the first exchange.
      final secondHistory =
          repo.refineCalls[1]['history'] as List<Map<String, String>>;
      expect(secondHistory, hasLength(2));

      expect(secondHistory[0]['role'], 'user');
      expect(secondHistory[0]['content'], 'First request');

      expect(secondHistory[1]['role'], 'assistant');
      expect(secondHistory[1]['content'], 'Turn 1 done.');
    });

    testWidgets(
        'on refine failure (ok:false) the friendly summary still appears as an assistant bubble',
        (tester) async {
      final repo = await _pumpSheetHost(tester);
      // Throw so the notifier returns ok:false with its fallback message.
      repo.enqueue(_FakeRefineControl(summary: '', throws: true));

      await tester.enterText(find.byType(CupertinoTextField), 'Make it better');
      await tester.pump();
      await tester.tap(find.byIcon(CupertinoIcons.arrow_up_circle_fill));
      await tester.pumpAndSettle();

      // The notifier's ok:false path emits a fallback friendly message.
      expect(
        find.textContaining("Sorry, I couldn't refine the setlist"),
        findsOneWidget,
      );

      // The user bubble is still visible — no crash, no blank screen.
      expect(find.text('Make it better'), findsOneWidget);
    });

    testWidgets(
        'send button is disabled and spinner shown while isRefining',
        (tester) async {
      final repo = await _pumpSheetHost(tester);

      // Use a completer so the refine call suspends indefinitely.
      final completer = Completer<RefineResult>();
      repo.enqueue(_FakeRefineControl(summary: '')..completer = completer);

      await tester.enterText(find.byType(CupertinoTextField), 'Pause me');
      await tester.pump();
      await tester.tap(find.byIcon(CupertinoIcons.arrow_up_circle_fill));
      // Pump a frame so the user bubble appears and the async call starts,
      // but do NOT pumpAndSettle — we want to inspect the in-progress state.
      await tester.pump();

      // The send button should be disabled (onPressed == null).
      final sendButton = tester.widget<CupertinoButton>(
        find.ancestor(
          of: find.byIcon(CupertinoIcons.arrow_up_circle_fill),
          matching: find.byType(CupertinoButton),
        ),
      );
      expect(sendButton.onPressed, isNull);

      // A CupertinoActivityIndicator (spinner) should be visible.
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);

      // The text field should be disabled while refining.
      final textField = tester.widget<CupertinoTextField>(
        find.byType(CupertinoTextField),
      );
      expect(textField.enabled, isFalse);

      // Resolve the completer so the widget can fully settle.
      completer.complete(const RefineResult(
        setlist: EventSetlist(id: 1, status: 'draft', songs: []),
        summary: 'All done.',
      ));
      await tester.pumpAndSettle();

      // After settling, the send button should be enabled again.
      final sendButtonAfter = tester.widget<CupertinoButton>(
        find.ancestor(
          of: find.byIcon(CupertinoIcons.arrow_up_circle_fill),
          matching: find.byType(CupertinoButton),
        ),
      );
      expect(sendButtonAfter.onPressed, isNotNull);
    });
  });
}
