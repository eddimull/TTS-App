/// A visibility rule. [dependsOn] is always a String: the server sends the
/// referenced field's DB id (stringified here); the editor sends client ids
/// ('id-dbId' / 'tmp-n') which the server rewrites on save.
class VisibilityRule {
  const VisibilityRule({
    required this.dependsOn,
    required this.operator,
    this.value,
  });

  final String dependsOn;
  final String operator; // equals | not_equals | contains | empty | not_empty
  final dynamic value;

  factory VisibilityRule.fromJson(Map<String, dynamic> json) {
    return VisibilityRule(
      dependsOn: '${json['depends_on']}',
      operator: json['operator'] as String? ?? 'equals',
      value: json['value'],
    );
  }

  Map<String, dynamic> toJson() =>
      {'depends_on': dependsOn, 'operator': operator, 'value': value};

  VisibilityRule copyWith({String? dependsOn, String? operator, dynamic value}) {
    return VisibilityRule(
      dependsOn: dependsOn ?? this.dependsOn,
      operator: operator ?? this.operator,
      value: value,
    );
  }
}

class FieldOption {
  const FieldOption({required this.label, required this.value});

  final String label;
  final String value;

  factory FieldOption.fromJson(Map<String, dynamic> json) => FieldOption(
        label: json['label'] as String? ?? '',
        value: '${json['value'] ?? ''}',
      );

  Map<String, dynamic> toJson() => {'label': label, 'value': value};
}

class QuestionnaireField {
  const QuestionnaireField({
    required this.id,
    required this.type,
    required this.label,
    this.helpText,
    required this.required,
    required this.position,
    this.settings,
    this.visibilityRule,
    this.mappingTarget,
    this.mappingLabel,
  });

  final int id;
  final String type;
  final String label;
  final String? helpText;
  final bool required;
  final int position;
  final Map<String, dynamic>? settings;
  final VisibilityRule? visibilityRule;
  final String? mappingTarget;
  final String? mappingLabel;

  List<FieldOption> get options {
    final raw = settings?['options'] as List<dynamic>? ?? [];
    return raw
        .map((o) => FieldOption.fromJson(o as Map<String, dynamic>))
        .toList();
  }

  factory QuestionnaireField.fromJson(Map<String, dynamic> json) {
    final rawRule = json['visibility_rule'] as Map<String, dynamic>?;
    return QuestionnaireField(
      id: (json['id'] as num).toInt(),
      type: json['type'] as String? ?? 'short_text',
      label: json['label'] as String? ?? '',
      helpText: json['help_text'] as String?,
      required: (json['required'] as bool?) ?? false,
      position: (json['position'] as num?)?.toInt() ?? 0,
      settings: json['settings'] as Map<String, dynamic>?,
      visibilityRule: rawRule == null ? null : VisibilityRule.fromJson(rawRule),
      mappingTarget: json['mapping_target'] as String?,
      mappingLabel: json['mapping_label'] as String?,
    );
  }
}
