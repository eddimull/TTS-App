# Save AI Rehearsal Plan to Notes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user save the AI planner's generated plan onto a rehearsal by writing it into the rehearsal's existing `notes` field, via an explicit "Save to rehearsal notes" button.

**Architecture:** A pure formatter turns a `PlannerPlan` into notes text. A new `savePlanToNotes` method on the planner notifier writes it through the existing `RehearsalsRepository.updateNotes` (`PATCH /api/mobile/rehearsals/{id}/notes`) — no backend changes. The plan card gains a Save button; if the rehearsal already has notes, a Cupertino action sheet offers Append / Replace / Cancel. On success the planner pops with `true` and the rehearsal detail screen re-fetches its notes.

**Tech Stack:** Flutter, Cupertino widgets, Riverpod v2 (`Notifier` / `NotifierProvider.family`), Dio, GoRouter.

## Global Constraints

- Cupertino widgets only (no Material). Follow existing patterns in the touched files.
- All colors resolve from context (`.resolveFrom(context)` / the `context` color extensions in `lib/core/theme/context_colors.dart`) — never raw fixed colors — so dark mode works.
- No backend changes, no new API endpoints, no new models beyond a pure formatter helper.
- The planner is always rehearsal-scoped in the current UI (`PlannerArgs.rehearsalId` non-null), but `savePlanToNotes` must guard against a null `rehearsalId` and no-op safely.
- Every code step shows the full code. Commit after each task.
- Test commands: `flutter test <path>` for a file, `flutter analyze <path>` for lint.

---

### Task 1: Plan → notes-text formatter

**Files:**
- Create: `lib/features/rehearsal_planner/data/models/planner_plan_formatter.dart`
- Test: `test/features/rehearsal_planner/models/planner_plan_formatter_test.dart`

**Interfaces:**
- Consumes: `PlannerPlan`, `PlannerPlanItem` from `lib/features/rehearsal_planner/data/models/planner_plan.dart`. For reference, their shapes are:
  - `PlannerPlan({required String title, required List<PlannerPlanItem> items})`
  - `PlannerPlanItem({int? songId, required String title, required String reason})`
- Produces: top-level function `String formatPlanAsNotes(PlannerPlan plan)`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/rehearsal_planner/models/planner_plan_formatter_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/rehearsal_planner/data/models/planner_plan.dart';
import 'package:tts_bandmate/features/rehearsal_planner/data/models/planner_plan_formatter.dart';

void main() {
  test('formats title, blank line, then one bullet per item', () {
    final plan = PlannerPlan(
      title: 'Rehearsal plan — Smith Wedding',
      items: const [
        PlannerPlanItem(title: 'At Last', reason: 'On the setlist, not rehearsed recently.'),
        PlannerPlanItem(title: 'Fly Me to the Moon', reason: 'Requested for the reception.'),
      ],
    );
    expect(
      formatPlanAsNotes(plan),
      'Rehearsal plan — Smith Wedding\n\n'
      '• At Last — On the setlist, not rehearsed recently.\n'
      '• Fly Me to the Moon — Requested for the reception.',
    );
  });

  test('item with empty reason has no trailing dash', () {
    final plan = PlannerPlan(
      title: 'Plan',
      items: const [PlannerPlanItem(title: 'Song A', reason: '')],
    );
    expect(formatPlanAsNotes(plan), 'Plan\n\n• Song A');
  });

  test('empty items returns just the title line', () {
    final plan = PlannerPlan(title: 'Empty plan', items: const []);
    expect(formatPlanAsNotes(plan), 'Empty plan');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/rehearsal_planner/models/planner_plan_formatter_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'planner_plan_formatter.dart'` (formatter not created yet).

- [ ] **Step 3: Write the formatter**

```dart
// lib/features/rehearsal_planner/data/models/planner_plan_formatter.dart
import 'planner_plan.dart';

/// Renders a [PlannerPlan] as plain text suitable for a rehearsal's notes field.
///
/// Layout: the title, a blank line, then one `• <title> — <reason>` bullet per
/// item. An item with an empty reason renders as just `• <title>` (no trailing
/// dash). A plan with no items renders as just the title line.
String formatPlanAsNotes(PlannerPlan plan) {
  if (plan.items.isEmpty) return plan.title;
  final bullets = plan.items.map((item) {
    final reason = item.reason.trim();
    return reason.isEmpty ? '• ${item.title}' : '• ${item.title} — $reason';
  }).join('\n');
  return '${plan.title}\n\n$bullets';
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/rehearsal_planner/models/planner_plan_formatter_test.dart`
Expected: PASS — all 3 tests green.

- [ ] **Step 5: Commit**

```bash
git add lib/features/rehearsal_planner/data/models/planner_plan_formatter.dart \
        test/features/rehearsal_planner/models/planner_plan_formatter_test.dart
git commit -m "feat(rehearsal-planner): add plan-to-notes text formatter"
```

---

### Task 2: `savePlanToNotes` on the planner notifier

**Files:**
- Modify: `lib/features/rehearsal_planner/providers/rehearsal_planner_provider.dart`
- Test: `test/features/rehearsal_planner/rehearsal_planner_provider_test.dart` (add cases)

**Interfaces:**
- Consumes:
  - `formatPlanAsNotes(PlannerPlan)` from Task 1.
  - `rehearsalsRepositoryProvider` (a `Provider<RehearsalsRepository>`) from `lib/features/rehearsals/data/rehearsals_repository.dart`; method `Future<String?> updateNotes(int rehearsalId, String? notes)`.
  - Existing `PlannerArgs` (has `int bandId`, `int? rehearsalId`), `RehearsalPlannerState`, `RehearsalPlannerNotifier`.
- Produces:
  - `enum NotesSaveMode { replace, append }`
  - Added state field `bool isSavingPlan` on `RehearsalPlannerState` (default `false`, threaded through `copyWith`).
  - Method `Future<bool> savePlanToNotes(PlannerPlan plan, {required NotesSaveMode mode, String? existingNotes})`.

- [ ] **Step 1: Write the failing tests**

Add these imports at the top of `test/features/rehearsal_planner/rehearsal_planner_provider_test.dart` (alongside the existing imports):

```dart
import 'package:tts_bandmate/features/rehearsal_planner/data/models/planner_plan.dart';
import 'package:tts_bandmate/features/rehearsals/data/rehearsals_repository.dart';
```

Add a fake `RehearsalsRepository` above `void main()` (it only needs `updateNotes`; other methods throw as they're never called). `RehearsalsRepository` is a concrete class, so extend it and pass a dummy `Dio` to `super`, overriding only `updateNotes`:

```dart
import 'package:dio/dio.dart';

class FakeRehearsalsRepo extends RehearsalsRepository {
  FakeRehearsalsRepo() : super(Dio());

  int? lastRehearsalId;
  String? lastNotes;
  bool shouldThrow = false;

  @override
  Future<String?> updateNotes(int rehearsalId, String? notes) async {
    if (shouldThrow) throw Exception('network');
    lastRehearsalId = rehearsalId;
    lastNotes = notes;
    return notes;
  }
}
```

Update `makeContainer()` to accept and register the fake so `savePlanToNotes` reaches it. Change the signature and the overrides list:

```dart
  late FakeRehearsalsRepo rehearsalsRepo;

  ProviderContainer makeContainer() {
    onEvent = null;
    rehearsalsRepo = FakeRehearsalsRepo();
    return ProviderContainer(overrides: [
      rehearsalPlannerRepositoryProvider.overrideWithValue(FakeRepo()),
      rehearsalsRepositoryProvider.overrideWithValue(rehearsalsRepo),
      plannerStreamBinderProvider
          .overrideWithValue((channel, cb) => onEvent = cb),
    ]);
  }
```

Then add these tests inside `main()`:

```dart
  final samplePlan = PlannerPlan(
    title: 'Plan',
    items: const [PlannerPlanItem(title: 'Song A', reason: 'because')],
  );

  test('savePlanToNotes(replace) writes formatted plan to the rehearsal id', () async {
    final c = makeContainer();
    addTearDown(c.dispose);
    final n = c.read(rehearsalPlannerProvider(args).notifier);

    final ok = await n.savePlanToNotes(samplePlan, mode: NotesSaveMode.replace);

    expect(ok, isTrue);
    expect(rehearsalsRepo.lastRehearsalId, 1); // args.rehearsalId
    expect(rehearsalsRepo.lastNotes, 'Plan\n\n• Song A — because');
    expect(c.read(rehearsalPlannerProvider(args)).isSavingPlan, isFalse);
  });

  test('savePlanToNotes(append) prepends existing notes with a blank line', () async {
    final c = makeContainer();
    addTearDown(c.dispose);
    final n = c.read(rehearsalPlannerProvider(args).notifier);

    final ok = await n.savePlanToNotes(
      samplePlan,
      mode: NotesSaveMode.append,
      existingNotes: 'Old notes',
    );

    expect(ok, isTrue);
    expect(rehearsalsRepo.lastNotes, 'Old notes\n\nPlan\n\n• Song A — because');
  });

  test('savePlanToNotes(append) with empty existing behaves like replace', () async {
    final c = makeContainer();
    addTearDown(c.dispose);
    final n = c.read(rehearsalPlannerProvider(args).notifier);

    await n.savePlanToNotes(samplePlan, mode: NotesSaveMode.append, existingNotes: '');

    expect(rehearsalsRepo.lastNotes, 'Plan\n\n• Song A — because');
  });

  test('savePlanToNotes returns false and sets error when the repo throws', () async {
    final c = makeContainer();
    addTearDown(c.dispose);
    rehearsalsRepo.shouldThrow = true;
    final n = c.read(rehearsalPlannerProvider(args).notifier);

    final ok = await n.savePlanToNotes(samplePlan, mode: NotesSaveMode.replace);

    expect(ok, isFalse);
    expect(c.read(rehearsalPlannerProvider(args)).error, isNotNull);
    expect(c.read(rehearsalPlannerProvider(args)).isSavingPlan, isFalse);
  });

  test('savePlanToNotes returns false without calling repo when rehearsalId is null', () async {
    const noRehearsalArgs = PlannerArgs(bandId: 7); // rehearsalId null
    final c = makeContainer();
    addTearDown(c.dispose);
    final n = c.read(rehearsalPlannerProvider(noRehearsalArgs).notifier);

    final ok = await n.savePlanToNotes(samplePlan, mode: NotesSaveMode.replace);

    expect(ok, isFalse);
    expect(rehearsalsRepo.lastRehearsalId, isNull); // never called
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/rehearsal_planner/rehearsal_planner_provider_test.dart`
Expected: FAIL — `The method 'savePlanToNotes' isn't defined`, `Undefined name 'NotesSaveMode'`, and `isSavingPlan` not defined. (Existing tests still pass.)

- [ ] **Step 3: Add the enum, state field, and method**

In `lib/features/rehearsal_planner/providers/rehearsal_planner_provider.dart`:

Add these imports near the existing model imports at the top:

```dart
import '../../rehearsals/data/rehearsals_repository.dart';
import '../data/models/planner_plan_formatter.dart';
```

Add the enum just above `class RehearsalPlannerState` (top-level):

```dart
/// How a saved plan combines with the rehearsal's current notes.
enum NotesSaveMode { replace, append }
```

Add `isSavingPlan` to `RehearsalPlannerState`. Update the constructor, the field
list, and `copyWith`:

```dart
class RehearsalPlannerState {
  const RehearsalPlannerState({
    this.messages = const [],
    this.isStarting = false,
    this.isSending = false,
    this.isSavingPlan = false,
    this.error,
    this.sessionId,
  });

  final List<PlannerMessage> messages;
  final bool isStarting;
  final bool isSending;
  final bool isSavingPlan;
  final String? error;
  final int? sessionId;

  RehearsalPlannerState copyWith({
    List<PlannerMessage>? messages,
    bool? isStarting,
    bool? isSending,
    bool? isSavingPlan,
    String? Function()? error,
    int? sessionId,
  }) =>
      RehearsalPlannerState(
        messages: messages ?? this.messages,
        isStarting: isStarting ?? this.isStarting,
        isSending: isSending ?? this.isSending,
        isSavingPlan: isSavingPlan ?? this.isSavingPlan,
        error: error != null ? error() : this.error,
        sessionId: sessionId ?? this.sessionId,
      );
}
```

Add the method inside `RehearsalPlannerNotifier` (e.g. after `send`):

```dart
  /// Writes [plan] into the scoped rehearsal's notes. Returns true on success.
  /// With [NotesSaveMode.append] and non-empty [existingNotes], the plan is
  /// added below the current notes; otherwise the plan replaces them.
  Future<bool> savePlanToNotes(
    PlannerPlan plan, {
    required NotesSaveMode mode,
    String? existingNotes,
  }) async {
    final rehearsalId = _args.rehearsalId;
    if (rehearsalId == null) return false;

    final planText = formatPlanAsNotes(plan);
    final existing = existingNotes?.trim() ?? '';
    final text = (mode == NotesSaveMode.append && existing.isNotEmpty)
        ? '$existing\n\n$planText'
        : planText;

    state = state.copyWith(isSavingPlan: true, error: () => null);
    try {
      await ref
          .read(rehearsalsRepositoryProvider)
          .updateNotes(rehearsalId, text);
      state = state.copyWith(isSavingPlan: false);
      return true;
    } catch (e) {
      state = state.copyWith(isSavingPlan: false, error: () => e.toString());
      return false;
    }
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/rehearsal_planner/rehearsal_planner_provider_test.dart`
Expected: PASS — the 5 new tests plus all pre-existing tests green.

- [ ] **Step 5: Commit**

```bash
git add lib/features/rehearsal_planner/providers/rehearsal_planner_provider.dart \
        test/features/rehearsal_planner/rehearsal_planner_provider_test.dart
git commit -m "feat(rehearsal-planner): savePlanToNotes writes plan to rehearsal notes"
```

---

### Task 3: Save button + action sheet on the planner screen

**Files:**
- Modify: `lib/features/rehearsal_planner/screens/rehearsal_planner_screen.dart`
- Test: `test/features/rehearsal_planner/rehearsal_planner_screen_test.dart` (add a case)

**Interfaces:**
- Consumes: `savePlanToNotes(...)`, `NotesSaveMode`, `isSavingPlan` from Task 2.
- Produces:
  - `RehearsalPlannerScreen` and `_PlannerView` gain an `String? existingNotes` param.
  - `_PlanCard` gains `bool isSaving` and `VoidCallback onSave`, and renders a "Save to rehearsal notes" button.
  - On successful save, the screen pops with `true` (`context.pop(true)` from `go_router`).

- [ ] **Step 1: Write the failing widget test**

Add this test inside `main()` in `test/features/rehearsal_planner/rehearsal_planner_screen_test.dart`. It mirrors the existing `renders streaming opening bubble` test's harness (same three overrides + `onEvent` driving), then fires a `done` event whose payload carries a `plan` so `message.plan != null`, which makes `_PlanCard` (and its Save button) render:

```dart
  testWidgets('renders Save to rehearsal notes button when a plan is present',
      (tester) async {
    void Function(String, Map<String, dynamic>)? onEvent;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          selectedBandProvider.overrideWith(() => _FakeBandNotifier(7)),
          rehearsalPlannerRepositoryProvider.overrideWithValue(FakeRepo()),
          plannerStreamBinderProvider.overrideWithValue((c, cb) => onEvent = cb),
        ],
        child: const CupertinoApp(
          home: RehearsalPlannerScreen(rehearsalId: 42, rehearsalLabel: 'July 15, 2026'),
        ),
      ),
    );
    await tester.pump(); // selectedBandProvider resolves + postFrame start()
    await tester.pump(); // startSession future completes
    await tester.pump(); // state rebuild flushes

    // Finalize the streaming opening message with a plan payload.
    onEvent!('done', {
      'message_id': 100,
      'content': 'Here is a plan.',
      'suggestions': <String>[],
      'plan': {
        'title': 'Plan',
        'items': [
          {'title': 'Song', 'reason': 'r'},
        ],
      },
    });
    await tester.pump();

    expect(find.text('Save to rehearsal notes'), findsOneWidget);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/rehearsal_planner/rehearsal_planner_screen_test.dart`
Expected: FAIL — `Save to rehearsal notes` text not found (button not built yet).

- [ ] **Step 3: Add the `existingNotes` param to the screen and view**

In `rehearsal_planner_screen.dart`, add the field to `RehearsalPlannerScreen`:

```dart
class RehearsalPlannerScreen extends ConsumerWidget {
  const RehearsalPlannerScreen({
    super.key,
    required this.rehearsalId,
    this.rehearsalLabel,
    this.existingNotes,
  });

  final int rehearsalId;
  final String? rehearsalLabel;

  /// The rehearsal's current notes, passed from the detail screen so the save
  /// flow can offer Append vs Replace. Null/empty means "no existing notes".
  final String? existingNotes;
```

Pass it through to `_PlannerView` in the `data:` builder:

```dart
        return _PlannerView(
          bandId: bandId,
          rehearsalId: rehearsalId,
          rehearsalLabel: rehearsalLabel,
          existingNotes: existingNotes,
        );
```

Add the field to `_PlannerView`:

```dart
class _PlannerView extends ConsumerStatefulWidget {
  const _PlannerView({
    required this.bandId,
    required this.rehearsalId,
    this.rehearsalLabel,
    this.existingNotes,
  });
  final int bandId;
  final int rehearsalId;
  final String? rehearsalLabel;
  final String? existingNotes;
```

- [ ] **Step 4: Add the save orchestration to `_PlannerViewState`**

Add this method to `_PlannerViewState`:

```dart
  Future<void> _onSavePlan(PlannerPlan plan) async {
    final notifier = ref.read(rehearsalPlannerProvider(_args).notifier);
    final existing = widget.existingNotes?.trim() ?? '';

    NotesSaveMode? mode;
    if (existing.isEmpty) {
      mode = NotesSaveMode.replace; // nothing to preserve → just write it
    } else {
      mode = await showCupertinoModalPopup<NotesSaveMode>(
        context: context,
        builder: (sheetContext) => CupertinoActionSheet(
          title: const Text('Save plan to notes'),
          message: const Text('This rehearsal already has notes.'),
          actions: [
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(sheetContext, NotesSaveMode.append),
              child: const Text('Append to notes'),
            ),
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(sheetContext, NotesSaveMode.replace),
              child: const Text('Replace notes'),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(sheetContext),
            child: const Text('Cancel'),
          ),
        ),
      );
    }

    if (mode == null) return; // user cancelled
    if (!mounted) return;

    final ok = await notifier.savePlanToNotes(
      plan,
      mode: mode,
      existingNotes: widget.existingNotes,
    );
    if (ok && mounted) context.pop(true);
    // On failure the provider set state.error; the existing error banner shows it.
  }
```

Ensure the file imports `PlannerPlan` and `go_router`. It already imports
`planner_plan.dart`. Add at the top if missing:

```dart
import 'package:go_router/go_router.dart';
```

- [ ] **Step 5: Thread `onSave` / `isSaving` down to `_PlanCard`**

In `_PlannerViewState.build`, the `ListView.builder` builds `_Bubble`s. Pass the
save wiring through. Update the `_Bubble` construction to include the plan-save
callback and saving flag:

```dart
                      itemBuilder: (_, i) => _Bubble(
                        message: state.messages[i],
                        onSuggestionTap: (s) => notifier.send(s),
                        onRetry: notifier.retryLast,
                        isSavingPlan: state.isSavingPlan,
                        onSavePlan: _onSavePlan,
                      ),
```

Update `_Bubble` to accept and forward these to `_PlanCard`:

```dart
class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.onSuggestionTap,
    required this.onRetry,
    required this.isSavingPlan,
    required this.onSavePlan,
  });

  final PlannerMessage message;
  final void Function(String) onSuggestionTap;
  final VoidCallback onRetry;
  final bool isSavingPlan;
  final Future<void> Function(PlannerPlan) onSavePlan;
```

And where `_PlanCard` is built:

```dart
        if (message.plan != null)
          _PlanCard(
            plan: message.plan!,
            isSaving: isSavingPlan,
            onSave: () => onSavePlan(message.plan!),
          ),
```

- [ ] **Step 6: Add the Save button to `_PlanCard`**

Update `_PlanCard` to take the new params and render the button below the items:

```dart
class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.isSaving,
    required this.onSave,
  });
  final PlannerPlan plan;
  final bool isSaving;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            plan.title,
            style: TextStyle(fontWeight: FontWeight.w600, color: context.primaryText),
          ),
          const SizedBox(height: 6),
          for (final item in plan.items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(
                '• ${item.title} — ${item.reason}',
                style: TextStyle(fontSize: 14, color: context.secondaryText),
              ),
            ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(vertical: 10),
              color: CupertinoColors.activeBlue.resolveFrom(context),
              borderRadius: BorderRadius.circular(8),
              onPressed: isSaving ? null : onSave,
              child: isSaving
                  ? const CupertinoActivityIndicator(color: CupertinoColors.white)
                  : const Text('Save to rehearsal notes',
                      style: TextStyle(color: CupertinoColors.white, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 7: Run the widget test + analyze**

Run: `flutter test test/features/rehearsal_planner/rehearsal_planner_screen_test.dart`
Expected: PASS — including the new "renders Save to rehearsal notes button" test and the pre-existing streaming/composer test.

Run: `flutter analyze lib/features/rehearsal_planner/screens/rehearsal_planner_screen.dart`
Expected: `No issues found!`

- [ ] **Step 8: Commit**

```bash
git add lib/features/rehearsal_planner/screens/rehearsal_planner_screen.dart \
        test/features/rehearsal_planner/rehearsal_planner_screen_test.dart
git commit -m "feat(rehearsal-planner): Save-to-notes button + append/replace sheet"
```

---

### Task 4: Pass notes into the planner route and refresh on return

**Files:**
- Modify: `lib/core/config/router.dart:401-410` (planner GoRoute)
- Modify: `lib/features/rehearsals/screens/rehearsal_detail_screen.dart` (planner button push + a refresh method)

**Interfaces:**
- Consumes: `RehearsalPlannerScreen({..., String? existingNotes})` from Task 3; `RehearsalsRepository.getRehearsalDetail(int) -> Future<RehearsalDetail>` and `rehearsalsRepositoryProvider` from `lib/features/rehearsals/data/rehearsals_repository.dart`.
- Produces: no new public API — wires `existingNotes` in and refreshes `_notes` after a `true` pop result.

- [ ] **Step 1: Decode `existingNotes` in the router**

In `lib/core/config/router.dart`, the planner route builder currently reads only
`rehearsalLabel`. Add `existingNotes`:

```dart
      GoRoute(
        path: '/rehearsals/:id/planner',
        builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return RehearsalPlannerScreen(
            rehearsalId: int.parse(state.pathParameters['id']!),
            rehearsalLabel: extra?['rehearsalLabel'] as String?,
            existingNotes: extra?['existingNotes'] as String?,
          );
        },
      ),
```

- [ ] **Step 2: Pass current notes and await the result in the detail screen**

In `lib/features/rehearsals/screens/rehearsal_detail_screen.dart`, the planner
button currently calls `context.push(...)` fire-and-forget. Replace its
`onPressed` (around lines 149-152) to pass `existingNotes` and await the result:

```dart
                onPressed: () async {
                  final saved = await context.push<bool>(
                    '/rehearsals/${rehearsal.id}/planner',
                    extra: {
                      'rehearsalLabel': _formatDateShort(rehearsal.date),
                      'existingNotes': _notes,
                    },
                  );
                  if (saved == true) {
                    await _refreshNotes(rehearsal.id);
                  }
                },
```

- [ ] **Step 3: Add the `_refreshNotes` method**

Add this method to `_RehearsalDetailViewState` (near `_saveNotes`). It re-fetches
the rehearsal and updates the locally-held notes so the Notes section reflects the
saved plan:

```dart
  Future<void> _refreshNotes(int rehearsalId) async {
    try {
      final repo = ref.read(rehearsalsRepositoryProvider);
      final fresh = await repo.getRehearsalDetail(rehearsalId);
      if (!mounted) return;
      setState(() {
        _notes = (fresh.notes?.isEmpty ?? true) ? null : fresh.notes;
        _notesController.text = _notes ?? '';
      });
    } catch (_) {
      // Non-fatal: the plan was saved server-side; a manual refresh will show it.
    }
  }
```

Confirm the file already imports `rehearsals_repository.dart` (it does, line 8) and
that `ref` is available (the state extends `ConsumerState`, so `ref` is in scope).

- [ ] **Step 4: Analyze both files**

Run: `flutter analyze lib/core/config/router.dart lib/features/rehearsals/screens/rehearsal_detail_screen.dart`
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/core/config/router.dart \
        lib/features/rehearsals/screens/rehearsal_detail_screen.dart
git commit -m "feat(rehearsals): pass notes to planner and refresh after saving a plan"
```

---

### Task 5: Full verification

**Files:** none (verification only).

- [ ] **Step 1: Run the full planner + rehearsals test suites**

Run: `flutter test test/features/rehearsal_planner/ test/features/rehearsals/`
Expected: PASS — all tests green.

- [ ] **Step 2: Analyze the whole project**

Run: `flutter analyze`
Expected: `No issues found!` (or no NEW issues vs. a clean baseline).

- [ ] **Step 3: Manual smoke (optional but recommended)**

Using the `run-on-device` skill or `flutter run`, open an upcoming rehearsal →
tap the sparkles planner → ask the AI for a plan → tap "Save to rehearsal notes".
Verify: with empty notes it saves and pops back showing the plan in Notes; with
existing notes the Append/Replace sheet appears and the chosen behavior is
correct.

- [ ] **Step 4: Confirm nothing extra changed**

Run: `git status` and `git log --oneline origin/main..HEAD`
Expected: only the 4 feature commits (Tasks 1-4) plus the earlier spec commit;
no stray files.
