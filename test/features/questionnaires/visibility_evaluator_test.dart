import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/questionnaires/data/models/questionnaire_field.dart';
import 'package:tts_bandmate/features/questionnaires/logic/visibility_evaluator.dart';

VisibilityFieldRef ref(String id, {VisibilityRule? rule}) =>
    VisibilityFieldRef(id: id, rule: rule);

void main() {
  test('test_no_rule_is_visible', () {
    expect(isFieldVisible('a', [ref('a')], {}), true);
  });

  test('test_unknown_field_is_visible', () {
    expect(isFieldVisible('missing', [ref('a')], {}), true);
  });

  test('test_missing_rule_target_is_visible', () {
    final fields = [
      ref('b', rule: const VisibilityRule(dependsOn: 'gone', operator: 'equals', value: 'x')),
    ];
    expect(isFieldVisible('b', fields, {}), true);
  });

  test('test_equals_matches_string_coercion', () {
    final fields = [
      ref('a'),
      ref('b', rule: const VisibilityRule(dependsOn: 'a', operator: 'equals', value: 'yes')),
    ];
    expect(isFieldVisible('b', fields, {'a': 'yes'}), true);
    expect(isFieldVisible('b', fields, {'a': 'no'}), false);
    expect(isFieldVisible('b', fields, {}), false);
  });

  test('test_equals_with_array_value_uses_contains', () {
    final fields = [
      ref('a'),
      ref('b', rule: const VisibilityRule(dependsOn: 'a', operator: 'equals', value: 'gold')),
    ];
    expect(isFieldVisible('b', fields, {'a': ['gold', 'silver']}), true);
    expect(isFieldVisible('b', fields, {'a': ['silver']}), false);
  });

  test('test_not_equals', () {
    final fields = [
      ref('a'),
      ref('b', rule: const VisibilityRule(dependsOn: 'a', operator: 'not_equals', value: 'yes')),
    ];
    expect(isFieldVisible('b', fields, {'a': 'no'}), true);
    expect(isFieldVisible('b', fields, {'a': 'yes'}), false);
  });

  test('test_contains_string_and_array', () {
    final fields = [
      ref('a'),
      ref('b', rule: const VisibilityRule(dependsOn: 'a', operator: 'contains', value: 'and',),),
    ];
    expect(isFieldVisible('b', fields, {'a': 'band night'}), true);
    expect(isFieldVisible('b', fields, {'a': 'quiet'}), false);
    expect(isFieldVisible('b', fields, {'a': ['grand entrance', 'exit']}), true);
    expect(isFieldVisible('b', fields, {'a': ['exit']}), false);
  });

  test('test_empty_and_not_empty', () {
    final fields = [
      ref('a'),
      ref('b', rule: const VisibilityRule(dependsOn: 'a', operator: 'empty')),
      ref('c', rule: const VisibilityRule(dependsOn: 'a', operator: 'not_empty')),
    ];
    expect(isFieldVisible('b', fields, {}), true);
    expect(isFieldVisible('b', fields, {'a': ''}), true);
    expect(isFieldVisible('b', fields, {'a': <String>[]}), true);
    expect(isFieldVisible('b', fields, {'a': 'x'}), false);
    expect(isFieldVisible('c', fields, {'a': 'x'}), true);
    expect(isFieldVisible('c', fields, {}), false);
  });

  test('test_hidden_dependency_cascades', () {
    // c depends on b; b depends on a and is hidden -> c hidden too.
    final fields = [
      ref('a'),
      ref('b', rule: const VisibilityRule(dependsOn: 'a', operator: 'equals', value: 'yes')),
      ref('c', rule: const VisibilityRule(dependsOn: 'b', operator: 'not_empty')),
    ];
    expect(isFieldVisible('c', fields, {'a': 'no', 'b': 'filled'}), false);
    expect(isFieldVisible('c', fields, {'a': 'yes', 'b': 'filled'}), true);
  });

  test('test_unknown_operator_hides', () {
    final fields = [
      ref('a'),
      ref('b', rule: const VisibilityRule(dependsOn: 'a', operator: 'bogus', value: 'x')),
    ];
    expect(isFieldVisible('b', fields, {'a': 'x'}), false);
  });
}
