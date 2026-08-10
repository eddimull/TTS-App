import 'package:tts_bandmate/features/help/data/help_repository.dart';
import 'package:tts_bandmate/features/help/data/models/help_article.dart';

/// Shared fake repository for help-center tests (providers + screen).
class FakeHelpRepository implements HelpRepository {
  @override
  Future<HelpIndex> getIndex() async => const HelpIndex(
        articles: [
          HelpArticle(
            slug: 'created-a-band',
            title: 'You created a band',
            category: 'getting-started',
            platforms: ['web', 'mobile'],
            order: 10,
          ),
          HelpArticle(
            slug: 'faq-payouts',
            title: 'How do payouts work?',
            category: 'faq',
            platforms: ['web', 'mobile'],
            order: 20,
          ),
          HelpArticle(
            slug: 'faq-live-setlist',
            title: 'How does the live setlist work during a performance?',
            category: 'faq',
            platforms: ['web', 'mobile'],
            order: 30,
          ),
        ],
        categoryLabels: {
          'getting-started': 'Getting started',
          'faq': 'FAQ',
        },
      );

  @override
  Future<HelpArticle> getArticle(String slug) async => HelpArticle(
        slug: slug,
        title: 'A',
        category: 'faq',
        platforms: const ['mobile'],
        order: 1,
        markdown: '## Hi',
      );
}
