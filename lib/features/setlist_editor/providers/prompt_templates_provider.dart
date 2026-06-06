import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/setlist_prompt_template.dart';
import '../data/setlist_editor_repository.dart';

/// Band-scoped list of saved AI prompt templates, keyed by band id.
///
/// Follows the house family-AsyncNotifier pattern (constructor-injected arg +
/// no-arg build), matching [bandSettingsProvider]. CRUD methods mutate the
/// already-loaded list locally so the UI updates without a full refetch.
class PromptTemplatesNotifier extends AsyncNotifier<List<SetlistPromptTemplate>> {
  PromptTemplatesNotifier(this._bandId);

  final int _bandId;

  SetlistEditorRepository get _repo => ref.read(setlistEditorRepositoryProvider);

  @override
  Future<List<SetlistPromptTemplate>> build() {
    return _repo.listPromptTemplates(_bandId);
  }

  // Note: named `edit` (not `update`) to avoid clashing with the inherited
  // AsyncNotifier.update(cb) method.
  List<SetlistPromptTemplate> get _current => state.value ?? const [];

  Future<SetlistPromptTemplate> create({
    required String name,
    required String prompt,
  }) async {
    final tpl = await _repo.createPromptTemplate(_bandId, name: name, prompt: prompt);
    state = AsyncData([..._current, tpl]..sort(_byName));
    return tpl;
  }

  Future<SetlistPromptTemplate> edit(int id, {String? name, String? prompt}) async {
    final tpl =
        await _repo.updatePromptTemplate(_bandId, id, name: name, prompt: prompt);
    state = AsyncData([
      for (final t in _current) t.id == id ? tpl : t,
    ]..sort(_byName));
    return tpl;
  }

  Future<void> delete(int id) async {
    await _repo.deletePromptTemplate(_bandId, id);
    state = AsyncData(_current.where((t) => t.id != id).toList());
  }

  static int _byName(SetlistPromptTemplate a, SetlistPromptTemplate b) =>
      a.name.toLowerCase().compareTo(b.name.toLowerCase());
}

final promptTemplatesProvider = AsyncNotifierProvider.family<
    PromptTemplatesNotifier, List<SetlistPromptTemplate>, int>(
  (arg) => PromptTemplatesNotifier(arg),
);
