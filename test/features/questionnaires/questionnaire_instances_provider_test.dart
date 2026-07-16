import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/questionnaires/data/models/questionnaire_instance.dart';
import 'package:tts_bandmate/features/questionnaires/providers/questionnaire_instances_provider.dart';
import 'package:tts_bandmate/features/questionnaires/providers/questionnaires_provider.dart';
import 'fake_questionnaires_repository.dart';

const _key = (bandId: 1, questionnaireId: 1);

QuestionnaireInstance instance(int id, {String status = 'sent'}) =>
    QuestionnaireInstance(
      id: id,
      name: 'Intake',
      status: status,
      recipientName: 'Alice',
      bookingId: 3,
      bookingName: 'Smith Wedding',
      questionnaireId: 1,
    );

void main() {
  ProviderContainer makeContainer(FakeQuestionnairesRepository repo) {
    return ProviderContainer(
      overrides: [questionnairesRepositoryProvider.overrideWithValue(repo)],
    );
  }

  test('test_build_loads_instances', () async {
    final repo = FakeQuestionnairesRepository(instances: [instance(7)]);
    final container = makeContainer(repo);
    addTearDown(container.dispose);

    final list = await container.read(questionnaireInstancesProvider(_key).future);
    expect(list.single.id, 7);
  });

  test('test_send_prepends_and_records_args', () async {
    final repo = FakeQuestionnairesRepository(instances: [instance(7)]);
    final container = makeContainer(repo);
    addTearDown(container.dispose);
    await container.read(questionnaireInstancesProvider(_key).future);

    final created = await container
        .read(questionnaireInstancesProvider(_key).notifier)
        .send(bookingId: 3, recipientContactId: 12);

    expect(created.id, isNot(7));
    expect(repo.sentBookingId, 3);
    expect(repo.sentContactId, 12);
    expect(repo.sentQuestionnaireId, 1);
    final list = container.read(questionnaireInstancesProvider(_key)).value!;
    expect(list.first.id, created.id); // prepended
    expect(list.length, 2);
  });

  test('test_lock_replaces_row', () async {
    final repo = FakeQuestionnairesRepository(instances: [instance(7)]);
    final container = makeContainer(repo);
    addTearDown(container.dispose);
    await container.read(questionnaireInstancesProvider(_key).future);

    await container
        .read(questionnaireInstancesProvider(_key).notifier)
        .lock(7);

    final list = container.read(questionnaireInstancesProvider(_key)).value!;
    expect(list.single.status, 'locked');
  });

  test('test_delete_removes_row', () async {
    final repo = FakeQuestionnairesRepository(instances: [instance(7)]);
    final container = makeContainer(repo);
    addTearDown(container.dispose);
    await container.read(questionnaireInstancesProvider(_key).future);

    await container
        .read(questionnaireInstancesProvider(_key).notifier)
        .deleteInstance(7);

    expect(repo.deletedInstanceId, 7);
    expect(container.read(questionnaireInstancesProvider(_key)).value, isEmpty);
  });
}
