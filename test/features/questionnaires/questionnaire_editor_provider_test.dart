import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/questionnaires/data/models/questionnaire.dart';
import 'package:tts_bandmate/features/questionnaires/data/models/questionnaire_field.dart';
import 'package:tts_bandmate/features/questionnaires/providers/questionnaire_editor_provider.dart';
import 'package:tts_bandmate/features/questionnaires/providers/questionnaires_provider.dart';
import 'fake_questionnaires_repository.dart';

const _key = (bandId: 1, questionnaireId: 1);

final _saved = Questionnaire(
  id: 1,
  name: 'Wedding Intake',
  instancesCount: 0,
  fields: [
    QuestionnaireField.fromJson({
      'id': 5, 'type': 'yes_no', 'label': 'Onsite?', 'position': 10, 'required': true,
    }),
    QuestionnaireField.fromJson({
      'id': 6, 'type': 'short_text', 'label': 'Details', 'position': 20,
      'visibility_rule': {'depends_on': 5, 'operator': 'equals', 'value': 'yes'},
    }),
  ],
);

void main() {
  ProviderContainer makeContainer(FakeQuestionnairesRepository repo) {
    return ProviderContainer(
      overrides: [questionnairesRepositoryProvider.overrideWithValue(repo)],
    );
  }

  test('test_load_maps_ids_to_client_ids', () async {
    final repo = FakeQuestionnairesRepository(questionnaires: [_saved]);
    final container = makeContainer(repo);
    addTearDown(container.dispose);

    final state = await container.read(questionnaireEditorProvider(_key).future);

    expect(state.dirty, false);
    expect(state.fields[0].clientId, 'id-5');
    expect(state.fields[1].visibilityRule!.dependsOn, 'id-5');
  });

  test('test_addField_marks_dirty_and_defaults_settings', () async {
    final repo = FakeQuestionnairesRepository(questionnaires: [_saved]);
    final container = makeContainer(repo);
    addTearDown(container.dispose);
    await container.read(questionnaireEditorProvider(_key).future);
    final notifier = container.read(questionnaireEditorProvider(_key).notifier);

    final added = notifier.addField('dropdown');

    expect(added.clientId, startsWith('tmp-'));
    expect(added.settings, {'options': <Map<String, dynamic>>[]});
    final state = container.read(questionnaireEditorProvider(_key)).value!;
    expect(state.dirty, true);
    expect(state.fields.length, 3);
  });

  test('test_removeField_clears_dependent_rules', () async {
    final repo = FakeQuestionnairesRepository(questionnaires: [_saved]);
    final container = makeContainer(repo);
    addTearDown(container.dispose);
    await container.read(questionnaireEditorProvider(_key).future);
    final notifier = container.read(questionnaireEditorProvider(_key).notifier);

    notifier.removeField('id-5');

    final state = container.read(questionnaireEditorProvider(_key)).value!;
    expect(state.fields.length, 1);
    expect(state.fields.single.visibilityRule, null);
  });

  test('test_reorder_moves_down_with_index_shift', () async {
    final repo = FakeQuestionnairesRepository(questionnaires: [_saved]);
    final container = makeContainer(repo);
    addTearDown(container.dispose);
    await container.read(questionnaireEditorProvider(_key).future);
    final notifier = container.read(questionnaireEditorProvider(_key).notifier);

    notifier.reorder(0, 2); // ReorderableListView "move first below second"

    final state = container.read(questionnaireEditorProvider(_key)).value!;
    expect(state.fields.map((f) => f.clientId).toList(), ['id-6', 'id-5']);
    expect(state.dirty, true);
  });

  test('test_save_sends_payload_and_resets_dirty', () async {
    final repo = FakeQuestionnairesRepository(questionnaires: [_saved]);
    final container = makeContainer(repo);
    addTearDown(container.dispose);
    await container.read(questionnaireEditorProvider(_key).future);
    final notifier = container.read(questionnaireEditorProvider(_key).notifier);

    notifier.setName('Renamed');
    await notifier.save();

    expect(repo.updatedName, 'Renamed');
    final sent = repo.updatedFields!;
    expect(sent[0]['client_id'], 'id-5');
    expect(sent[0]['position'], 10);
    expect(sent[1]['position'], 20);
    expect(sent[1]['visibility_rule'], {
      'depends_on': 'id-5', 'operator': 'equals', 'value': 'yes',
    });
    expect(container.read(questionnaireEditorProvider(_key)).value!.dirty, false);
  });

  test('test_duplicateField_strips_id_and_copies', () async {
    final repo = FakeQuestionnairesRepository(questionnaires: [_saved]);
    final container = makeContainer(repo);
    addTearDown(container.dispose);
    await container.read(questionnaireEditorProvider(_key).future);
    final notifier = container.read(questionnaireEditorProvider(_key).notifier);

    notifier.duplicateField('id-5');

    final state = container.read(questionnaireEditorProvider(_key)).value!;
    expect(state.fields.length, 3);
    final copy = state.fields[1]; // inserted right after the original
    expect(copy.id, null);
    expect(copy.clientId, startsWith('tmp-'));
    expect(copy.label, 'Onsite? (copy)');
  });
}
