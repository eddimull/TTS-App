class FieldTypeDef {
  const FieldTypeDef({
    required this.type,
    required this.label,
    required this.isInput,
    this.requiredSettings = const [],
  });

  final String type;
  final String label;
  final bool isInput;
  final List<String> requiredSettings;

  factory FieldTypeDef.fromJson(Map<String, dynamic> json) => FieldTypeDef(
        type: json['type'] as String? ?? '',
        label: json['label'] as String? ?? '',
        isInput: (json['is_input'] as bool?) ?? true,
        requiredSettings: (json['required_settings'] as List<dynamic>? ?? [])
            .map((s) => s as String)
            .toList(),
      );
}

class MappingTargetDef {
  const MappingTargetDef({
    required this.key,
    required this.label,
    this.compatibleFieldTypes = const [],
  });

  final String key;
  final String label;
  final List<String> compatibleFieldTypes;

  factory MappingTargetDef.fromJson(Map<String, dynamic> json) =>
      MappingTargetDef(
        key: json['key'] as String? ?? '',
        label: json['label'] as String? ?? '',
        compatibleFieldTypes:
            (json['compatible_field_types'] as List<dynamic>? ?? [])
                .map((t) => t as String)
                .toList(),
      );
}

class PresetDef {
  const PresetDef({
    required this.key,
    required this.name,
    required this.description,
    required this.fieldCount,
  });

  final String key;
  final String name;
  final String description;
  final int fieldCount;

  factory PresetDef.fromJson(Map<String, dynamic> json) => PresetDef(
        key: json['key'] as String? ?? '',
        name: json['name'] as String? ?? '',
        description: json['description'] as String? ?? '',
        fieldCount: (json['field_count'] as num?)?.toInt() ?? 0,
      );
}

class QuestionnaireCatalog {
  const QuestionnaireCatalog({
    this.fieldTypes = const [],
    this.mappingTargets = const [],
    this.presets = const [],
  });

  final List<FieldTypeDef> fieldTypes;
  final List<MappingTargetDef> mappingTargets;
  final List<PresetDef> presets;

  factory QuestionnaireCatalog.fromJson(Map<String, dynamic> json) =>
      QuestionnaireCatalog(
        fieldTypes: (json['field_types'] as List<dynamic>? ?? [])
            .map((t) => FieldTypeDef.fromJson(t as Map<String, dynamic>))
            .toList(),
        mappingTargets: (json['mapping_targets'] as List<dynamic>? ?? [])
            .map((t) => MappingTargetDef.fromJson(t as Map<String, dynamic>))
            .toList(),
        presets: (json['presets'] as List<dynamic>? ?? [])
            .map((p) => PresetDef.fromJson(p as Map<String, dynamic>))
            .toList(),
      );
}
