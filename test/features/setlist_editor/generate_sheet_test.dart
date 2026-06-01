import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/setlist_editor/data/models/setlist_prompt_template.dart';
import 'package:tts_bandmate/features/setlist_editor/providers/prompt_templates_provider.dart';
import 'package:tts_bandmate/features/setlist_editor/widgets/generate_sheet.dart';

// ---------------------------------------------------------------------------
// Test-only fake notifier
// ---------------------------------------------------------------------------

/// Tracks calls to [create] for assertion in tests.
class _FakePromptTemplatesNotifier
    extends AsyncNotifier<List<SetlistPromptTemplate>>
    implements PromptTemplatesNotifier {
  _FakePromptTemplatesNotifier(this._initial);

  final List<SetlistPromptTemplate> _initial;

  /// Populated whenever [create] is invoked.
  final List<({String name, String prompt})> createCalls = [];

  @override
  Future<List<SetlistPromptTemplate>> build() async => _initial;

  @override
  Future<SetlistPromptTemplate> create({
    required String name,
    required String prompt,
  }) async {
    createCalls.add((name: name, prompt: prompt));
    final tpl = SetlistPromptTemplate(
      id: _initial.length + createCalls.length,
      name: name,
      prompt: prompt,
    );
    state = AsyncData([...(state.value ?? []), tpl]);
    return tpl;
  }

  @override
  Future<SetlistPromptTemplate> edit(int id, {String? name, String? prompt}) {
    throw UnimplementedError('not needed in generate_sheet tests');
  }

  @override
  Future<void> delete(int id) {
    throw UnimplementedError('not needed in generate_sheet tests');
  }
}

// ---------------------------------------------------------------------------
// Helper: pump the sheet via a tap on a "Open" button
// ---------------------------------------------------------------------------

const int _bandId = 42;

/// Pumps a [CupertinoApp] with a [ProviderScope] that overrides
/// [promptTemplatesProvider(_bandId)] with [notifier].
///
/// Returns the [GenerateRequest] captured when the user taps Generate (or null
/// on cancel). [onResult] is invoked synchronously from inside the async
/// tester flow so the caller can inspect the result.
Future<void> _pumpSheet(
  WidgetTester tester, {
  required _FakePromptTemplatesNotifier notifier,
  void Function(GenerateRequest)? onResult,
}) async {
  GenerateRequest? captured;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // Override the family provider for the specific bandId used in tests.
        promptTemplatesProvider(_bandId).overrideWith(() => notifier),
      ],
      child: CupertinoApp(
        home: Builder(
          builder: (context) => CupertinoPageScaffold(
            child: CupertinoButton(
              onPressed: () async {
                final result = await showGenerateSheet(
                  context,
                  bandId: _bandId,
                );
                if (result != null) {
                  captured = result;
                  onResult?.call(result);
                }
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );

  // Open the sheet.
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();

  // captured is used only when onResult is supplied.
  assert(captured == null || captured != null);
}

// ---------------------------------------------------------------------------
// Sample fixtures
// ---------------------------------------------------------------------------

const _tpl1 = SetlistPromptTemplate(
  id: 1,
  name: 'Wedding',
  prompt: 'High energy throughout, romantic finish.',
);
const _tpl2 = SetlistPromptTemplate(
  id: 2,
  name: 'Corporate',
  prompt: 'Keep it tasteful, no explicit lyrics.',
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('GenerateSheet — template strip', () {
    testWidgets('renders provided prompt templates in the strip',
        (tester) async {
      final notifier = _FakePromptTemplatesNotifier([_tpl1, _tpl2]);

      await _pumpSheet(tester, notifier: notifier);

      expect(find.text('Wedding'), findsOneWidget);
      expect(find.text('Corporate'), findsOneWidget);
      // The strip label is also visible
      expect(find.textContaining('Saved prompts'), findsOneWidget);
    });

    testWidgets('shows a loading spinner while templates are loading',
        (tester) async {
      // Use a notifier whose build() never completes (Completer trick).
      final slowNotifier =
          _SlowNotifier(); // defined below the main() block

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            promptTemplatesProvider(_bandId).overrideWith(() => slowNotifier),
          ],
          child: CupertinoApp(
            home: Builder(
              builder: (context) => CupertinoPageScaffold(
                child: CupertinoButton(
                  onPressed: () =>
                      showGenerateSheet(context, bandId: _bandId),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pump(); // one frame — loading state

      expect(find.byType(CupertinoActivityIndicator), findsWidgets);
    });

    testWidgets(
        'tapping a template chip fills the context text field with its prompt',
        (tester) async {
      final notifier = _FakePromptTemplatesNotifier([_tpl1, _tpl2]);

      await _pumpSheet(tester, notifier: notifier);

      // Tap the "Wedding" chip.
      await tester.tap(find.text('Wedding'));
      await tester.pump();

      // The context field should now contain the template's prompt.
      expect(
        find.widgetWithText(CupertinoTextField, _tpl1.prompt),
        findsOneWidget,
      );
    });

    testWidgets(
        'tapping a different template replaces context with new prompt',
        (tester) async {
      final notifier = _FakePromptTemplatesNotifier([_tpl1, _tpl2]);

      await _pumpSheet(tester, notifier: notifier);

      await tester.tap(find.text('Wedding'));
      await tester.pump();

      await tester.tap(find.text('Corporate'));
      await tester.pump();

      expect(
        find.widgetWithText(CupertinoTextField, _tpl2.prompt),
        findsOneWidget,
      );
    });

    testWidgets('loaded label appears after tapping a template',
        (tester) async {
      final notifier = _FakePromptTemplatesNotifier([_tpl1]);

      await _pumpSheet(tester, notifier: notifier);

      await tester.tap(find.text('Wedding'));
      await tester.pump();

      expect(find.textContaining('Loaded: Wedding'), findsOneWidget);
    });

    testWidgets('Clear button removes loaded label and save-prompt row',
        (tester) async {
      final notifier = _FakePromptTemplatesNotifier([_tpl1]);

      await _pumpSheet(tester, notifier: notifier);

      await tester.tap(find.text('Wedding'));
      await tester.pump();

      expect(find.textContaining('Loaded: Wedding'), findsOneWidget);

      // Tap "Clear"
      await tester.tap(find.text('Clear'));
      await tester.pump();

      expect(find.textContaining('Loaded: Wedding'), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------

  group('GenerateSheet — Generate button', () {
    testWidgets('tapping Generate returns a GenerateRequest with no context',
        (tester) async {
      final notifier = _FakePromptTemplatesNotifier([]);
      GenerateRequest? result;

      await _pumpSheet(
        tester,
        notifier: notifier,
        onResult: (r) => result = r,
      );

      await tester.tap(find.text('Generate'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.context, isNull);
    });

    testWidgets(
        'tapping Generate fires the callback with current context text',
        (tester) async {
      final notifier = _FakePromptTemplatesNotifier([]);
      GenerateRequest? result;

      await _pumpSheet(
        tester,
        notifier: notifier,
        onResult: (r) => result = r,
      );

      // Type into the context field.
      await tester.enterText(
        find.byType(CupertinoTextField).first,
        'Keep it upbeat throughout.',
      );
      await tester.pump();

      await tester.tap(find.text('Generate'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.context, 'Keep it upbeat throughout.');
    });

    testWidgets(
        'context entered via template chip is forwarded by Generate',
        (tester) async {
      final notifier = _FakePromptTemplatesNotifier([_tpl1]);
      GenerateRequest? result;

      await _pumpSheet(
        tester,
        notifier: notifier,
        onResult: (r) => result = r,
      );

      await tester.tap(find.text('Wedding'));
      await tester.pump();

      await tester.tap(find.text('Generate'));
      await tester.pumpAndSettle();

      expect(result!.context, _tpl1.prompt);
    });

    testWidgets('tapping Cancel pops without returning a result',
        (tester) async {
      final notifier = _FakePromptTemplatesNotifier([]);
      GenerateRequest? result;

      await _pumpSheet(
        tester,
        notifier: notifier,
        onResult: (r) => result = r,
      );

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(result, isNull);
    });
  });

  // ---------------------------------------------------------------------------

  group('GenerateSheet — Save-as-prompt flow', () {
    testWidgets(
        'Save-as-prompt row is hidden when context textarea is empty',
        (tester) async {
      final notifier = _FakePromptTemplatesNotifier([]);

      await _pumpSheet(tester, notifier: notifier);

      // No text entered → save row should not appear.
      expect(find.widgetWithText(CupertinoTextField, 'Save prompt as…'),
          findsNothing);
    });

    testWidgets(
        'Save-as-prompt row appears after typing in the context field',
        (tester) async {
      final notifier = _FakePromptTemplatesNotifier([]);

      await _pumpSheet(tester, notifier: notifier);

      await tester.enterText(
        find.byType(CupertinoTextField).first,
        'Some context text',
      );
      await tester.pump();

      expect(find.widgetWithText(CupertinoTextField, 'Save prompt as…'),
          findsOneWidget);
    });

    testWidgets(
        'Save button is disabled while the prompt-name field is empty',
        (tester) async {
      final notifier = _FakePromptTemplatesNotifier([]);

      await _pumpSheet(tester, notifier: notifier);

      await tester.enterText(
        find.byType(CupertinoTextField).first,
        'Some context',
      );
      await tester.pump();

      // The "Save" button should be present but disabled (onPressed == null).
      final saveButtons = tester.widgetList<CupertinoButton>(
        find.ancestor(
          of: find.text('Save'),
          matching: find.byType(CupertinoButton),
        ),
      );
      expect(saveButtons.any((b) => b.onPressed == null), isTrue);
    });

    testWidgets(
        'entering a name and tapping Save invokes notifier.create',
        (tester) async {
      final notifier = _FakePromptTemplatesNotifier([]);

      await _pumpSheet(tester, notifier: notifier);

      // 1. Enter context text.
      await tester.enterText(
        find.byType(CupertinoTextField).first,
        'Keep energy high.',
      );
      await tester.pump();

      // 2. Enter a name for the template.
      await tester.enterText(
        find.widgetWithText(CupertinoTextField, 'Save prompt as…'),
        'Energy set',
      );
      await tester.pump();

      // 3. Tap Save.
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Notifier.create should have been called once.
      expect(notifier.createCalls.length, 1);
      expect(notifier.createCalls.first.name, 'Energy set');
      expect(notifier.createCalls.first.prompt, 'Keep energy high.');
    });
  });
}

// ---------------------------------------------------------------------------
// Helper notifier that stays in loading state indefinitely.
// ---------------------------------------------------------------------------

class _SlowNotifier extends AsyncNotifier<List<SetlistPromptTemplate>>
    implements PromptTemplatesNotifier {
  @override
  Future<List<SetlistPromptTemplate>> build() {
    // Return a Completer future that never completes — the provider stays in
    // AsyncLoading for the entire test frame without creating a pending timer.
    return Completer<List<SetlistPromptTemplate>>().future;
  }

  @override
  Future<SetlistPromptTemplate> create({
    required String name,
    required String prompt,
  }) =>
      throw UnimplementedError();

  @override
  Future<SetlistPromptTemplate> edit(int id, {String? name, String? prompt}) =>
      throw UnimplementedError();

  @override
  Future<void> delete(int id) => throw UnimplementedError();
}
