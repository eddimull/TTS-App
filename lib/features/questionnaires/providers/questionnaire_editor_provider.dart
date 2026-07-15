import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/questionnaire.dart';
import '../data/models/questionnaire_field.dart';
import 'questionnaires_provider.dart';

/// A field being edited. [clientId] is `id-<dbId>` for persisted fields and
/// `tmp-<n>` for new ones; visibility rules reference clientIds and the server
/// rewrites them to DB ids on save (same contract as the web builder).
class EditorField {
  const EditorField({
    required this.clientId,
    this.id,
    required this.type,
    required this.label,
    this.helpText,
    required this.required,
    required this.position,
    this.settings,
    this.visibilityRule,
    this.mappingTarget,
  });

  final String clientId;
  final int? id;
  final String type;
  final String label;
  final String? helpText;
  final bool required;
  final int position;
  final Map<String, dynamic>? settings;
  final VisibilityRule? visibilityRule;
  final String? mappingTarget;

  List<FieldOption> get options {
    final raw = settings?['options'] as List<dynamic>? ?? [];
    return raw
        .map((o) => FieldOption.fromJson(o as Map<String, dynamic>))
        .toList();
  }

  EditorField copyWith({
    String? type,
    String? label,
    String? helpText,
    bool clearHelpText = false,
    bool? required,
    int? position,
    Map<String, dynamic>? settings,
    bool clearSettings = false,
    VisibilityRule? visibilityRule,
    bool clearVisibilityRule = false,
    String? mappingTarget,
    bool clearMappingTarget = false,
  }) {
    return EditorField(
      clientId: clientId,
      id: id,
      type: type ?? this.type,
      label: label ?? this.label,
      helpText: clearHelpText ? null : (helpText ?? this.helpText),
      required: required ?? this.required,
      position: position ?? this.position,
      settings: clearSettings ? null : (settings ?? this.settings),
      visibilityRule:
          clearVisibilityRule ? null : (visibilityRule ?? this.visibilityRule),
      mappingTarget:
          clearMappingTarget ? null : (mappingTarget ?? this.mappingTarget),
    );
  }

  Map<String, dynamic> toPayload() => {
        'id': id,
        'client_id': clientId,
        'type': type,
        'label': label,
        'help_text': helpText,
        'required': required,
        'position': position,
        'settings': settings,
        'visibility_rule': visibilityRule?.toJson(),
        'mapping_target': mappingTarget,
      };
}

/// Maps a saved questionnaire's fields into editor fields, converting DB ids
/// (including visibility_rule.depends_on) to `id-<dbId>` client ids.
List<EditorField> editorFieldsFromQuestionnaire(Questionnaire q) {
  return q.fields.map((f) {
    final rule = f.visibilityRule;
    return EditorField(
      clientId: 'id-${f.id}',
      id: f.id,
      type: f.type,
      label: f.label,
      helpText: f.helpText,
      required: f.required,
      position: f.position,
      settings: f.settings,
      visibilityRule: rule == null
          ? null
          : VisibilityRule(
              dependsOn: 'id-${rule.dependsOn}',
              operator: rule.operator,
              value: rule.value,
            ),
      mappingTarget: f.mappingTarget,
    );
  }).toList();
}

class QuestionnaireEditorState {
  const QuestionnaireEditorState({
    required this.name,
    this.description,
    required this.fields,
    required this.dirty,
  });

  final String name;
  final String? description;
  final List<EditorField> fields;
  final bool dirty;

  QuestionnaireEditorState copyWith({
    String? name,
    String? description,
    bool clearDescription = false,
    List<EditorField>? fields,
    bool? dirty,
  }) {
    return QuestionnaireEditorState(
      name: name ?? this.name,
      description:
          clearDescription ? null : (description ?? this.description),
      fields: fields ?? this.fields,
      dirty: dirty ?? this.dirty,
    );
  }
}

class QuestionnaireEditorNotifier
    extends AsyncNotifier<QuestionnaireEditorState> {
  QuestionnaireEditorNotifier(this._key);

  final ({int bandId, int questionnaireId}) _key;
  int _nextClientId = 0;

  @override
  Future<QuestionnaireEditorState> build() async {
    final q = await ref
        .read(questionnairesRepositoryProvider)
        .getQuestionnaire(_key.bandId, _key.questionnaireId);
    return QuestionnaireEditorState(
      name: q.name,
      description: q.description,
      fields: editorFieldsFromQuestionnaire(q),
      dirty: false,
    );
  }

  QuestionnaireEditorState get _s => state.value!;

  void _emit(QuestionnaireEditorState next) {
    state = AsyncValue.data(next);
  }

  void setName(String name) =>
      _emit(_s.copyWith(name: name, dirty: true));

  void setDescription(String? description) => _emit(_s.copyWith(
        description: description,
        clearDescription: description == null,
        dirty: true,
      ));

  EditorField addField(String type) {
    final field = EditorField(
      clientId: 'tmp-${++_nextClientId}',
      type: type,
      label: '',
      required: false,
      position: (_s.fields.length + 1) * 10,
      settings: _defaultSettings(type),
    );
    _emit(_s.copyWith(fields: [..._s.fields, field], dirty: true));
    return field;
  }

  Map<String, dynamic>? _defaultSettings(String type) {
    switch (type) {
      case 'dropdown':
      case 'multi_select':
      case 'checkbox_group':
        return {'options': <Map<String, dynamic>>[]};
      case 'song_picker':
        return {'purpose': 'general'};
      default:
        return null;
    }
  }

  void updateField(EditorField updated) {
    _emit(_s.copyWith(
      fields: _s.fields
          .map((f) => f.clientId == updated.clientId ? updated : f)
          .toList(),
      dirty: true,
    ));
  }

  void duplicateField(String clientId) {
    final index = _s.fields.indexWhere((f) => f.clientId == clientId);
    if (index == -1) return;
    final original = _s.fields[index];
    final copy = EditorField(
      clientId: 'tmp-${++_nextClientId}',
      type: original.type,
      label: '${original.label} (copy)',
      helpText: original.helpText,
      required: original.required,
      position: original.position,
      settings: original.settings == null
          ? null
          : Map<String, dynamic>.from(original.settings!),
      visibilityRule: original.visibilityRule,
      mappingTarget: original.mappingTarget,
    );
    final fields = [..._s.fields]..insert(index + 1, copy);
    _emit(_s.copyWith(fields: fields, dirty: true));
  }

  void removeField(String clientId) {
    final fields = _s.fields
        .where((f) => f.clientId != clientId)
        .map((f) => f.visibilityRule?.dependsOn == clientId
            ? f.copyWith(clearVisibilityRule: true)
            : f)
        .toList();
    _emit(_s.copyWith(fields: fields, dirty: true));
  }

  void reorder(int oldIndex, int newIndex) {
    final fields = [..._s.fields];
    if (oldIndex < 0 || oldIndex >= fields.length) return;
    // ReorderableListView semantics: when moving down, target index shifts.
    if (oldIndex < newIndex) newIndex -= 1;
    final item = fields.removeAt(oldIndex);
    if (newIndex < 0) newIndex = 0;
    if (newIndex > fields.length) newIndex = fields.length;
    fields.insert(newIndex, item);
    _emit(_s.copyWith(fields: fields, dirty: true));
  }

  Future<void> save() async {
    final s = _s;
    final payload = <Map<String, dynamic>>[];
    for (var i = 0; i < s.fields.length; i++) {
      payload.add(s.fields[i].copyWith(position: (i + 1) * 10).toPayload());
    }
    final updated = await ref
        .read(questionnairesRepositoryProvider)
        .updateQuestionnaire(
          _key.bandId,
          _key.questionnaireId,
          name: s.name,
          description: s.description,
          fields: payload,
        );
    ref.invalidate(questionnairesProvider(_key.bandId));
    ref.invalidate(questionnaireDetailProvider(_key));
    _emit(QuestionnaireEditorState(
      name: updated.name,
      description: updated.description,
      fields: editorFieldsFromQuestionnaire(updated),
      dirty: false,
    ));
  }
}

final questionnaireEditorProvider = AsyncNotifierProvider.family<
    QuestionnaireEditorNotifier,
    QuestionnaireEditorState,
    ({int bandId, int questionnaireId})>(
  (arg) => QuestionnaireEditorNotifier(arg),
);
