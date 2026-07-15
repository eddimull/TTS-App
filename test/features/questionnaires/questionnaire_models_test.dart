import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/questionnaires/data/models/questionnaire.dart';
import 'package:tts_bandmate/features/questionnaires/data/models/questionnaire_catalog.dart';
import 'package:tts_bandmate/features/questionnaires/data/models/questionnaire_field.dart';

void main() {
  group('QuestionnaireField.fromJson', () {
    test('test_parses_all_fields', () {
      final field = QuestionnaireField.fromJson({
        'id': 5,
        'type': 'dropdown',
        'label': 'Package',
        'help_text': 'Pick one',
        'required': true,
        'position': 20,
        'settings': {
          'options': [
            {'label': 'Gold', 'value': 'gold'},
          ],
        },
        'visibility_rule': {'depends_on': 3, 'operator': 'equals', 'value': 'yes'},
        'mapping_target': 'wedding.onsite',
      });
      expect(field.id, 5);
      expect(field.type, 'dropdown');
      expect(field.helpText, 'Pick one');
      expect(field.required, true);
      expect(field.options.single.label, 'Gold');
      expect(field.options.single.value, 'gold');
      expect(field.visibilityRule!.dependsOn, '3'); // int stringified
      expect(field.visibilityRule!.operator, 'equals');
      expect(field.mappingTarget, 'wedding.onsite');
    });

    test('test_null_coalesces_optional_fields', () {
      final field = QuestionnaireField.fromJson({'id': 1, 'type': 'short_text', 'label': 'Name'});
      expect(field.helpText, null);
      expect(field.required, false);
      expect(field.position, 0);
      expect(field.settings, null);
      expect(field.options, isEmpty);
      expect(field.visibilityRule, null);
      expect(field.mappingTarget, null);
    });
  });

  group('Questionnaire.fromJson', () {
    test('test_parses_detail_with_fields', () {
      final q = Questionnaire.fromJson({
        'id': 1,
        'name': 'Wedding Intake',
        'description': 'For weddings',
        'archived_at': null,
        'instances_count': 2,
        'updated_at': '2026-07-15T10:00:00+00:00',
        'fields': [
          {'id': 10, 'type': 'header', 'label': 'Basics', 'position': 10},
        ],
      });
      expect(q.id, 1);
      expect(q.name, 'Wedding Intake');
      expect(q.isArchived, false);
      expect(q.instancesCount, 2);
      expect(q.fields.single.type, 'header');
    });

    test('test_archived_flag', () {
      final q = Questionnaire.fromJson({
        'id': 2,
        'name': 'Old',
        'archived_at': '2026-01-01T00:00:00+00:00',
      });
      expect(q.isArchived, true);
      expect(q.fields, isEmpty);
      expect(q.instancesCount, 0);
    });
  });

  group('QuestionnaireCatalog.fromJson', () {
    test('test_parses_catalogs', () {
      final catalog = QuestionnaireCatalog.fromJson({
        'field_types': [
          {'type': 'dropdown', 'label': 'Dropdown', 'is_input': true, 'required_settings': ['options']},
          {'type': 'header', 'label': 'Header', 'is_input': false, 'required_settings': []},
        ],
        'mapping_targets': [
          {'key': 'wedding.onsite', 'label': 'Onsite ceremony', 'compatible_field_types': ['yes_no']},
        ],
        'presets': [
          {'key': 'wedding', 'name': 'Wedding', 'description': 'Full wedding intake', 'field_count': 20},
        ],
      });
      expect(catalog.fieldTypes.first.requiredSettings, ['options']);
      expect(catalog.fieldTypes.last.isInput, false);
      expect(catalog.mappingTargets.single.compatibleFieldTypes, ['yes_no']);
      expect(catalog.presets.single.key, 'wedding');
    });
  });
}
