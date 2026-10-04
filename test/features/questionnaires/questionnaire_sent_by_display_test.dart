import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/auth/data/models/auth_user.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/auth/providers/auth_provider.dart';
import 'package:tts_bandmate/features/questionnaires/data/models/questionnaire.dart';
import 'package:tts_bandmate/features/questionnaires/data/models/questionnaire_instance.dart';
import 'package:tts_bandmate/features/questionnaires/providers/questionnaires_provider.dart';
import 'package:tts_bandmate/features/questionnaires/screens/instance_responses_screen.dart';
import 'package:tts_bandmate/features/questionnaires/screens/questionnaire_detail_screen.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';

import 'fake_questionnaires_repository.dart';

// Parity with the web: wherever a questionnaire instance shows its sent date,
// it also names the band user who sent it, for audit purposes.

class _FakeAuth extends AuthNotifier {
  @override
  Future<AuthState> build() async => const AuthAuthenticated(
        user: AuthUser(id: 1, name: 'Eddie', email: 'e@x.com'),
        bands: [BandSummary(id: 1, name: 'Band', isOwner: true)],
      );
}

class _FakeBand extends SelectedBandNotifier {
  @override
  Future<int?> build() async => 1;
}

QuestionnaireInstance _instance({String? sentByName}) => QuestionnaireInstance(
      id: 7,
      name: 'Wedding Intake',
      status: 'sent',
      sentAt: DateTime(2026, 7, 15, 10),
      sentByName: sentByName,
      recipientName: 'Alice',
      bookingId: 3,
      bookingName: 'Smith Wedding',
      questionnaireId: 1,
    );

Widget _app(FakeQuestionnairesRepository repo, Widget home) => ProviderScope(
      overrides: [
        questionnairesRepositoryProvider.overrideWithValue(repo),
        authProvider.overrideWith(_FakeAuth.new),
        selectedBandProvider.overrideWith(_FakeBand.new),
      ],
      child: CupertinoApp(home: home),
    );

FakeQuestionnairesRepository _repo({String? sentByName}) =>
    FakeQuestionnairesRepository(
      questionnaires: const [
        Questionnaire(id: 1, name: 'Wedding Intake', instancesCount: 1),
      ],
      instances: [_instance(sentByName: sentByName)],
    );

void main() {
  testWidgets('instance list row names the sender after the sent date',
      (tester) async {
    await tester.pumpWidget(_app(
      _repo(sentByName: 'Eddie Mullins'),
      const QuestionnaireDetailScreen(questionnaireId: 1),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('sent Jul 15, 2026 by Eddie Mullins'),
        findsOneWidget);
  });

  testWidgets('instance list row omits the sender when the backend has none',
      (tester) async {
    await tester.pumpWidget(_app(
      _repo(),
      const QuestionnaireDetailScreen(questionnaireId: 1),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('sent Jul 15, 2026'), findsOneWidget);
    expect(find.textContaining(' by '), findsNothing);
  });

  testWidgets('responses header names the sender after the sent date',
      (tester) async {
    await tester.pumpWidget(_app(
      _repo(sentByName: 'Eddie Mullins'),
      const InstanceResponsesScreen(questionnaireId: 1, instanceId: 7),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('by Eddie Mullins'), findsOneWidget);
  });
}
