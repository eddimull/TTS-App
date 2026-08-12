import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tts_bandmate/features/help/providers/help_providers.dart';
import 'fake_help_repository.dart';

void main() {
  test('helpIndexProvider exposes repository index', () async {
    final container = ProviderContainer(overrides: [
      helpRepositoryProvider.overrideWithValue(FakeHelpRepository()),
    ]);
    addTearDown(container.dispose);
    final index = await container.read(helpIndexProvider.future);
    expect(index.articles.first.slug, 'created-a-band');
  });

  test('helpArticleProvider fetches by slug', () async {
    final container = ProviderContainer(overrides: [
      helpRepositoryProvider.overrideWithValue(FakeHelpRepository()),
    ]);
    addTearDown(container.dispose);
    final article = await container.read(helpArticleProvider('a').future);
    expect(article.markdown, '## Hi');
  });
}
