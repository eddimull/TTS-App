import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/help/data/models/help_article.dart';

void main() {
  test('HelpArticle.fromJson parses full payload', () {
    final a = HelpArticle.fromJson({
      'slug': 'created-a-band',
      'title': 'You created a band',
      'category': 'getting-started',
      'platforms': ['web', 'mobile'],
      'order': 10,
      'updated_at': '2026-08-10T12:00:00+00:00',
      'markdown': '## Hello',
    });
    expect(a.slug, 'created-a-band');
    expect(a.platforms, contains('mobile'));
    expect(a.order, 10);
    expect(a.markdown, '## Hello');
    expect(a.updatedAt, isNotNull);
  });

  test('HelpArticle.fromJson tolerates missing fields', () {
    final a = HelpArticle.fromJson({'slug': 'x'});
    expect(a.title, '');
    expect(a.platforms, isEmpty);
    expect(a.markdown, isNull);
    expect(a.updatedAt, isNull);
  });

  test('HelpIndex.fromJson parses articles and labels', () {
    final idx = HelpIndex.fromJson({
      'articles': [
        {'slug': 'a', 'title': 'A', 'category': 'faq', 'platforms': ['mobile'], 'order': 1},
      ],
      'category_labels': {'faq': 'FAQ'},
    });
    expect(idx.articles, hasLength(1));
    expect(idx.categoryLabels['faq'], 'FAQ');
  });
}
