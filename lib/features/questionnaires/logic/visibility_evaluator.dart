import '../data/models/questionnaire_field.dart';

/// Dart port of TTS resources/js/Pages/Contact/Questionnaire/visibility.js
/// (which mirrors app/Services/QuestionnaireVisibilityEvaluator.php).
/// Any behavior change here MUST match those two files.
class VisibilityFieldRef {
  const VisibilityFieldRef({required this.id, this.rule});

  final String id;
  final VisibilityRule? rule;
}

bool isFieldVisible(
  String fieldId,
  List<VisibilityFieldRef> allFields,
  Map<String, dynamic> responses,
) {
  final field = _find(fieldId, allFields);
  if (field == null) return true;
  return _fieldIsVisible(field, allFields, responses);
}

bool _fieldIsVisible(
  VisibilityFieldRef field,
  List<VisibilityFieldRef> allFields,
  Map<String, dynamic> responses,
) {
  final rule = field.rule;
  if (rule == null) return true;

  final target = _find(rule.dependsOn, allFields);
  if (target == null) return true;

  if (!_fieldIsVisible(target, allFields, responses)) return false;

  return _evaluate(rule, responses[rule.dependsOn]);
}

VisibilityFieldRef? _find(String id, List<VisibilityFieldRef> allFields) {
  for (final f in allFields) {
    if (f.id == id) return f;
  }
  return null;
}

bool _evaluate(VisibilityRule rule, dynamic value) {
  final expected = rule.value;
  switch (rule.operator) {
    case 'equals':
      return _valueEquals(value, expected);
    case 'not_equals':
      return !_valueEquals(value, expected);
    case 'contains':
      return _valueContains(value, expected);
    case 'empty':
      return _valueIsEmpty(value);
    case 'not_empty':
      return !_valueIsEmpty(value);
    default:
      return false;
  }
}

bool _valueEquals(dynamic value, dynamic expected) {
  if (value is List) return value.contains(expected);
  return '$value' == '$expected';
}

bool _valueContains(dynamic value, dynamic expected) {
  final needle = '$expected';
  if (value is List) {
    return value.any((item) => item is String && item.contains(needle));
  }
  return value is String && value.contains(needle);
}

bool _valueIsEmpty(dynamic value) {
  if (value is List) return value.isEmpty;
  return value == null || value == '';
}
