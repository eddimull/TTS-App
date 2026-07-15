import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/questionnaires/data/models/questionnaire.dart';
import 'package:tts_bandmate/features/questionnaires/providers/questionnaires_provider.dart';
import 'fake_questionnaires_repository.dart';

const _q = Questionnaire(id: 1, name: 'Wedding Intake', instancesCount: 0);

void main() {
  ProviderContainer makeContainer(FakeQuestionnairesRepository repo) {
    return ProviderContainer(
      overrides: [
        questionnairesRepositoryProvider.overrideWithValue(repo),
      ],
    );
  }

  group('QuestionnairesNotifier', () {
    test('test_build_loads_questionnaires', () async {
      final repo = FakeQuestionnairesRepository(questionnaires: [_q]);
      final container = makeContainer(repo);
      addTearDown(container.dispose);

      final list = await container.read(questionnairesProvider(1).future);
      expect(list.single.name, 'Wedding Intake');
    });

    test('test_create_appends_and_returns_created', () async {
      final repo = FakeQuestionnairesRepository(questionnaires: [_q]);
      final container = makeContainer(repo);
      addTearDown(container.dispose);
      await container.read(questionnairesProvider(1).future);

      final created = await container
          .read(questionnairesProvider(1).notifier)
          .create(name: 'New', presetKey: 'wedding');

      expect(created.name, 'New');
      expect(repo.createdPresetKey, 'wedding');
      expect(container.read(questionnairesProvider(1)).value!.length, 2);
    });

    test('test_archive_replaces_in_list', () async {
      final repo = FakeQuestionnairesRepository(questionnaires: [_q]);
      final container = makeContainer(repo);
      addTearDown(container.dispose);
      await container.read(questionnairesProvider(1).future);

      await container.read(questionnairesProvider(1).notifier).archive(1);

      expect(repo.archivedId, 1);
      expect(container.read(questionnairesProvider(1)).value!.single.isArchived, true);
    });

    test('test_delete_removes_from_list', () async {
      final repo = FakeQuestionnairesRepository(questionnaires: [_q]);
      final container = makeContainer(repo);
      addTearDown(container.dispose);
      await container.read(questionnairesProvider(1).future);

      await container.read(questionnairesProvider(1).notifier).delete(1);

      expect(repo.deletedId, 1);
      expect(container.read(questionnairesProvider(1)).value, isEmpty);
    });
  });
}
