import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';
import '../data/models/help_article.dart';
import '../providers/help_providers.dart';

/// Help center index — "Getting started" articles as cards up top, then one
/// section per remaining category. Mounted from Settings > Help & Support
/// via GoRouter (/help).
class HelpScreen extends ConsumerWidget {
  const HelpScreen({super.key});

  static const _gettingStartedCategory = 'getting-started';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final indexAsync = ref.watch(helpIndexProvider);

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Help & Support'),
      ),
      child: SafeArea(
        child: indexAsync.when(
          loading: () => const Center(child: CupertinoActivityIndicator()),
          error: (_, __) => _ErrorState(
            onRetry: () => ref.invalidate(helpIndexProvider),
          ),
          data: (index) => _HelpIndexList(index: index),
        ),
      ),
    );
  }
}

// ── Content ───────────────────────────────────────────────────────────────────

class _HelpIndexList extends StatelessWidget {
  const _HelpIndexList({required this.index});

  final HelpIndex index;

  @override
  Widget build(BuildContext context) {
    final gettingStarted = <HelpArticle>[];
    // Preserve server order: articles already arrive sorted by category rank
    // then order, so a single forward pass buckets them without re-sorting.
    final byCategory = <String, List<HelpArticle>>{};
    final categoryOrder = <String>[];

    for (final article in index.articles) {
      if (article.category == HelpScreen._gettingStartedCategory) {
        gettingStarted.add(article);
        continue;
      }
      final bucket = byCategory.putIfAbsent(article.category, () {
        categoryOrder.add(article.category);
        return <HelpArticle>[];
      });
      bucket.add(article);
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        const SizedBox(height: 8),
        for (final article in gettingStarted)
          _GettingStartedCard(article: article),
        for (final category in categoryOrder) ...[
          _CategoryHeader(
            label: index.categoryLabels[category] ?? category,
          ),
          for (final article in byCategory[category]!)
            NavRowArticle(article: article),
        ],
      ],
    );
  }
}

/// "Getting started" article — full-width rounded tappable card, visually
/// distinct from the plain NavRow list below it.
class _GettingStartedCard extends StatelessWidget {
  const _GettingStartedCard({required this.article});

  final HelpArticle article;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: article.title,
      child: GestureDetector(
        onTap: () => context.push('/help/${article.slug}'),
        behavior: HitTestBehavior.opaque,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: CupertinoColors.systemBlue
                .resolveFrom(context)
                .withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  article.title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: CupertinoColors.systemBlue.resolveFrom(context),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                CupertinoIcons.chevron_right,
                size: 16,
                color: CupertinoColors.systemBlue.resolveFrom(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: context.secondaryText,
        ),
      ),
    );
  }
}

/// Plain article row for non-"getting started" categories. A thin wrapper
/// around the shared NavRow so titles wrap (not ellipsize) at narrow widths —
/// help article titles can run long and shouldn't be truncated in the index.
class NavRowArticle extends StatelessWidget {
  const NavRowArticle({super.key, required this.article});

  final HelpArticle article;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: article.title,
      child: GestureDetector(
        onTap: () => context.push('/help/${article.slug}'),
        behavior: HitTestBehavior.opaque,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          decoration: BoxDecoration(
            color:
                CupertinoColors.tertiarySystemBackground.resolveFrom(context),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  article.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                CupertinoIcons.chevron_right,
                size: 14,
                color: context.tertiaryText,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Error state ───────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.exclamationmark_circle,
              size: 44,
              color: context.secondaryText,
            ),
            const SizedBox(height: 12),
            Text(
              "Couldn't load Help & Support.",
              textAlign: TextAlign.center,
              style: TextStyle(color: context.secondaryText),
            ),
            const SizedBox(height: 16),
            CupertinoButton.filled(
              onPressed: onRetry,
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
