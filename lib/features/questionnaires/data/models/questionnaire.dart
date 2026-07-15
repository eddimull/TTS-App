import 'questionnaire_field.dart';

class Questionnaire {
  const Questionnaire({
    required this.id,
    required this.name,
    this.description,
    this.archivedAt,
    required this.instancesCount,
    this.updatedAt,
    this.fields = const [],
  });

  final int id;
  final String name;
  final String? description;
  final DateTime? archivedAt;
  final int instancesCount;
  final DateTime? updatedAt;
  final List<QuestionnaireField> fields;

  bool get isArchived => archivedAt != null;

  factory Questionnaire.fromJson(Map<String, dynamic> json) {
    final rawFields = json['fields'] as List<dynamic>? ?? [];
    return Questionnaire(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      archivedAt: json['archived_at'] == null
          ? null
          : DateTime.tryParse(json['archived_at'] as String),
      instancesCount: (json['instances_count'] as num?)?.toInt() ?? 0,
      updatedAt: json['updated_at'] == null
          ? null
          : DateTime.tryParse(json['updated_at'] as String),
      fields: rawFields
          .map((f) => QuestionnaireField.fromJson(f as Map<String, dynamic>))
          .toList(),
    );
  }

  Questionnaire copyWith({
    String? name,
    String? description,
    DateTime? archivedAt,
    bool clearArchivedAt = false,
    int? instancesCount,
    List<QuestionnaireField>? fields,
  }) {
    return Questionnaire(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      archivedAt: clearArchivedAt ? null : (archivedAt ?? this.archivedAt),
      instancesCount: instancesCount ?? this.instancesCount,
      updatedAt: updatedAt,
      fields: fields ?? this.fields,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Questionnaire &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Questionnaire(id: $id, name: $name)';
}
