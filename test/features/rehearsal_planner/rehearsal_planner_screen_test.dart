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
}
