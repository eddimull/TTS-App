import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/core_providers.dart';
import '../data/help_repository.dart';
import '../data/models/help_article.dart';

final helpRepositoryProvider = Provider<HelpRepository>((ref) {
  final dio = ref.watch(apiClientProvider).dio;
  return HelpRepository(dio);
});

/// Help center index. Invalidate to refresh.
final helpIndexProvider = FutureProvider.autoDispose<HelpIndex>((ref) async {
  return ref.watch(helpRepositoryProvider).getIndex();
});

/// One article, fetched by slug.
final helpArticleProvider =
    FutureProvider.autoDispose.family<HelpArticle, String>((ref, slug) async {
  return ref.watch(helpRepositoryProvider).getArticle(slug);
});
