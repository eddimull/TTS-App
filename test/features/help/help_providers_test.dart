import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tts_bandmate/features/help/data/help_repository.dart';
import 'package:tts_bandmate/features/help/data/models/help_article.dart';
import 'package:tts_bandmate/features/help/providers/help_providers.dart';

class _FakeHelpRepository implements HelpRepository {
  @override
  Future<HelpIndex> getIndex() async => const HelpIndex(
        articles: [
          HelpArticle(slug: 'a', title: 'A', category: 'faq', platforms: ['mobile'], order: 1),
        ],
        categoryLabels: {'faq': 'FAQ'},
      );

  @override
  Future<HelpArticle> getArticle(String slug) async => HelpArticle(
      slug: slug, title: 'A', category: 'faq', platforms: const ['mobile'], order: 1, markdown: '## Hi');
}

void main() {
  test('helpIndexProvider exposes repository index', () async {
    final container = ProviderContainer(overrides: [
      helpRepositoryProvider.overrideWithValue(_FakeHelpRepository()),
    ]);
    addTearDown(container.dispose);
    final index = await container.read(helpIndexProvider.future);
    expect(index.articles.single.slug, 'a');
  });

  test('helpArticleProvider fetches by slug', () async {
    final container = ProviderContainer(overrides: [
      helpRepositoryProvider.overrideWithValue(_FakeHelpRepository()),
    ]);
    addTearDown(container.dispose);
    final article = await container.read(helpArticleProvider('a').future);
    expect(article.markdown, '## Hi');
  });
}
