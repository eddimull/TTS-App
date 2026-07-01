import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/rehearsal_planner/data/models/planner_message.dart';
import 'package:tts_bandmate/features/rehearsal_planner/data/rehearsal_planner_repository.dart';
import 'package:tts_bandmate/features/rehearsal_planner/providers/rehearsal_planner_provider.dart';
import 'package:tts_bandmate/features/rehearsal_planner/screens/rehearsal_planner_screen.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';

// ── Fake repository ─────────────────────────────────────────────────────────

class FakeRepo implements RehearsalPlannerRepository {
  @override
  Future<({int sessionId, String channel, int assistantMessageId})>
      startSession(int bandId, {int? rehearsalId}) async =>
          (sessionId: 1, channel: 'c', assistantMessageId: 100);

  @override
  Future<({PlannerMessage userMessage, int assistantMessageId, String channel})>
      sendMessage(int b, int s, String t) async => (
            userMessage:
                PlannerMessage(id: 200, role: 'user', text: t, status: 'complete'),
            assistantMessageId: 201,
            channel: 'c',
          );

  @override
  Future<List<PlannerMessage>> history(int b, int s) async => [];
}

// ── Fake SelectedBandNotifier ────────────────────────────────────────────────

/// Resolves immediately to a fixed band ID without hitting secure storage.
class _FakeBandNotifier extends SelectedBandNotifier {
  _FakeBandNotifier(this._id);
  final int? _id;

  @override
  Future<int?> build() async => _id;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  testWidgets('renders streaming opening bubble and composer', (tester) async {
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
    // Pump to allow selectedBandProvider to resolve and postFrameCallback to fire.
    await tester.pump();
    // Allow start() async work (startSession future) to complete.
    await tester.pump();
    // One more pump to allow the state rebuild to flush.
    await tester.pump();

    // Composer present
    expect(find.byType(CupertinoTextField), findsOneWidget);

    // Drive a delta event and confirm it renders
    onEvent!('text_delta', {'delta': 'Hi there'});
    await tester.pump();
    expect(find.text('Hi there'), findsOneWidget);
  });

  testWidgets('auto-scrolls to bottom as streamed content grows',
      (tester) async {
    void Function(String, Map<String, dynamic>)? onEvent;

    // Constrain the viewport so a handful of long messages overflow it and
    // maxScrollExtent becomes > 0.
    tester.view.physicalSize = const Size(400, 500);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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
    await tester.pump();
    await tester.pump();
    await tester.pump();

    // Stream a long opening message so the single bubble alone doesn't
    // overflow; then send several more short-text turns (each producing a
    // long streamed assistant reply) so the list becomes scrollable. Keep
    // composer input short to avoid unrelated layout overflow.
    onEvent!('text_delta', {
      'delta': 'A ' * 200,
    });
    await tester.pump();

    for (var i = 0; i < 5; i++) {
      final controllerFinder = find.byType(CupertinoTextField);
      await tester.enterText(controllerFinder, 'Turn $i');
      await tester.pump();
      await tester.tap(find.byIcon(CupertinoIcons.arrow_up_circle_fill));
      // Allow sendMessage's fake future to resolve and rebuild.
      await tester.pump();
      await tester.pump();
      onEvent!('text_delta', {'delta': 'Reply $i ' * 80});
      await tester.pump();
      // Let each auto-scroll animation fully settle before adding more
      // content, so ListView.builder lays out far-off items and
      // maxScrollExtent reflects the true content height.
      await tester.pumpAndSettle();
    }

    final listView = tester.widget<ListView>(find.byType(ListView));
    final controller = listView.controller!;
    expect(controller.hasClients, isTrue);
    expect(
      controller.position.maxScrollExtent,
      greaterThan(0),
      reason: 'test content must overflow the viewport to exercise scrolling',
    );

    // Auto-scroll runs inside a post-frame callback with a 200ms animation;
    // pump once to let the last callback schedule/start the animation, then
    // settle it fully.
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      controller.position.pixels,
      closeTo(controller.position.maxScrollExtent, 1.0),
    );
  });
}
