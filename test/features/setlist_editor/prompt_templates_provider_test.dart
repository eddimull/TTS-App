import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/setlist_editor/data/models/setlist_prompt_template.dart';
import 'package:tts_bandmate/features/setlist_editor/data/setlist_editor_repository.dart';
import 'package:tts_bandmate/features/setlist_editor/providers/prompt_templates_provider.dart';

class _FakeRepo extends SetlistEditorRepository {
  _FakeRepo(this._initial) : super(Dio());

  final List<SetlistPromptTemplate> _initial;
  int _nextId = 100;
  final List<int> deleted = [];

  @override
  Future<List<SetlistPromptTemplate>> listPromptTemplates(int bandId) async =>
      _initial;

  @override
  Future<SetlistPromptTemplate> createPromptTemplate(
    int bandId, {
    required String name,
    required String prompt,
  }) async =>
      SetlistPromptTemplate(id: _nextId++, name: name, prompt: prompt);

  @override
  Future<SetlistPromptTemplate> updatePromptTemplate(
    int bandId,
    int templateId, {
    String? name,
    String? prompt,
  }) async =>
      SetlistPromptTemplate(
        id: templateId,
        name: name ?? 'unchanged',
        prompt: prompt ?? 'unchanged',
      );

  @override
  Future<void> deletePromptTemplate(int bandId, int templateId) async {
    deleted.add(templateId);
  }
}

ProviderContainer _container(_FakeRepo repo) => ProviderContainer(overrides: [
      setlistEditorRepositoryProvider.overrideWithValue(repo),
    ]);

void main() {
  test('build loads templates for the band', () async {
    final repo = _FakeRepo(const [
      SetlistPromptTemplate(id: 1, name: 'Wedding', prompt: 'High energy'),
    ]);
    final container = _container(repo);
    addTearDown(container.dispose);

    final list = await container.read(promptTemplatesProvider(7).future);
    expect(list.single.name, 'Wedding');
  });

  test('create appends and keeps the list sorted by name', () async {
    final repo = _FakeRepo(const [
      SetlistPromptTemplate(id: 1, name: 'Mellow', prompt: 'x'),
    ]);
    final container = _container(repo);
    addTearDown(container.dispose);

    await container.read(promptTemplatesProvider(7).future);
    await container
        .read(promptTemplatesProvider(7).notifier)
        .create(name: 'Anthemic', prompt: 'y');

    final list = container.read(promptTemplatesProvider(7)).requireValue;
    expect(list.map((t) => t.name).toList(), ['Anthemic', 'Mellow']);
  });

  test('edit replaces the matching template and keeps it sorted', () async {
    final repo = _FakeRepo(const [
      SetlistPromptTemplate(id: 1, name: 'Old', prompt: 'x'),
      SetlistPromptTemplate(id: 2, name: 'Keep', prompt: 'y'),
    ]);
    final container = _container(repo);
    addTearDown(container.dispose);

    await container.read(promptTemplatesProvider(7).future);
    await container
        .read(promptTemplatesProvider(7).notifier)
        .edit(1, name: 'New');

    final list = container.read(promptTemplatesProvider(7)).requireValue;
    expect(list.firstWhere((t) => t.id == 1).name, 'New');
    expect(list.length, 2);
    expect(list.map((t) => t.name).toList(), ['Keep', 'New']); // re-sorted
  });

  test('delete removes the template and calls the repo', () async {
    final repo = _FakeRepo(const [
      SetlistPromptTemplate(id: 1, name: 'Gone', prompt: 'x'),
      SetlistPromptTemplate(id: 2, name: 'Stay', prompt: 'y'),
    ]);
    final container = _container(repo);
    addTearDown(container.dispose);

    await container.read(promptTemplatesProvider(7).future);
    await container.read(promptTemplatesProvider(7).notifier).delete(1);

    final list = container.read(promptTemplatesProvider(7)).requireValue;
    expect(list.map((t) => t.id).toList(), [2]);
    expect(repo.deleted, [1]);
  });
}
