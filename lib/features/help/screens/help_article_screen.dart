import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';
import '../data/models/help_article.dart';
import '../providers/help_providers.dart';

/// What tapping a markdown link inside a help article should do: launch it
/// externally (any href with a URI scheme — http(s), mailto, tel, ...) or
/// navigate to another article (bare, scheme-less slugs from backend
/// cross-links).
sealed class HelpLinkAction {
  const HelpLinkAction();
}

class HelpLinkActionLaunch extends HelpLinkAction {
  const HelpLinkActionLaunch(this.uri);

  final Uri uri;
}

class HelpLinkActionNavigate extends HelpLinkAction {
  const HelpLinkActionNavigate(this.slug);

  final String slug;
}

/// Decides what a tapped markdown link href should do. Scheme-bearing hrefs
/// (http(s):, mailto:, tel:, ...) are launched externally; scheme-less hrefs
/// are treated as bare article slugs from backend cross-links and navigated
/// to in-app. Pulled out as a pure function so the branch can be unit tested
/// without mocking url_launcher — see help_article_screen_test.dart.
HelpLinkAction decideLinkAction(String href) {
  final uri = Uri.tryParse(href);
  if (uri != null && uri.hasScheme) {
    return HelpLinkActionLaunch(uri);
  }
  return HelpLinkActionNavigate(href);
}

/// A single help article, rendered from server-provided markdown. Pushed
/// from HelpScreen (or another article's cross-link) via GoRouter
/// (/help/:slug).
class HelpArticleScreen extends ConsumerWidget {
  const HelpArticleScreen({super.key, required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final articleAsync = ref.watch(helpArticleProvider(slug));

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        // Nothing to show until the title loads; avoids a slug-shaped
        // placeholder flashing in the nav bar.
        middle: articleAsync.maybeWhen(
          data: (article) => Text(article.title),
          orElse: () => null,
        ),
        previousPageTitle: 'Help',
      ),
      child: SafeArea(
        child: articleAsync.when(
          loading: () => const Center(child: CupertinoActivityIndicator()),
          error: (e, __) => _ArticleErrorState(error: e),
          data: (article) => _ArticleBody(article: article),
        ),
      ),
    );
  }
}

// ── Data state ───────────────────────────────────────────────────────────────

class _ArticleBody extends StatelessWidget {
  const _ArticleBody({required this.article});

  final HelpArticle article;

  @override
  Widget build(BuildContext context) {
    final baseStyle =
        MarkdownStyleSheet.fromCupertinoTheme(CupertinoTheme.of(context));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            article.title,
            style: CupertinoTheme.of(context)
                .textTheme
                .navLargeTitleTextStyle
                .copyWith(fontSize: 24),
          ),
          const SizedBox(height: 16),
          MarkdownBody(
            data: article.markdown ?? '',
            styleSheet: baseStyle.copyWith(
              p: baseStyle.p?.copyWith(height: 1.45),
              h2Padding: const EdgeInsets.only(top: 12, bottom: 4),
            ),
            onTapLink: (text, href, title) => _handleLinkTap(context, href),
          ),
        ],
      ),
    );
  }

  void _handleLinkTap(BuildContext context, String? href) {
    if (href == null || href.isEmpty) return;
    final action = decideLinkAction(href);
    switch (action) {
      case HelpLinkActionLaunch(:final uri):
        unawaited(
          launchUrl(uri, mode: LaunchMode.externalApplication)
              .catchError((_) => false),
        );
      case HelpLinkActionNavigate(:final slug):
        // Backend cross-links use bare slugs (e.g. "finances", "get-paid") —
        // some point at web-only articles the mobile API 404s on. The pushed
        // screen's own error state handles that gracefully.
        context.push('/help/$slug');
    }
  }
}

// ── Error state ───────────────────────────────────────────────────────────────

class _ArticleErrorState extends StatelessWidget {
  const _ArticleErrorState({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    // Cross-linked articles can point at web-only content the mobile API
    // 404s on — that's an expected, non-actionable outcome (retrying can't
    // fix a missing article), so it gets a friendly message and a way back
    // rather than a raw error dump or a Retry button.
    final isNotFound = error is DioException &&
        (error as DioException).response?.statusCode == 404;

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
              isNotFound
                  ? "This article isn't available."
                  : "Couldn't load this article.",
              textAlign: TextAlign.center,
              style: TextStyle(color: context.secondaryText),
            ),
            const SizedBox(height: 16),
            CupertinoButton.filled(
              onPressed: () => _backToHelp(context),
              child: const Text('Back to Help'),
            ),
          ],
        ),
      ),
    );
  }

  void _backToHelp(BuildContext context) {
    // This screen may be reached either by pushing from HelpScreen or by
    // chaining through another article's cross-link, so the stack depth
    // varies — pop if there's somewhere to land, otherwise go directly.
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/help');
    }
  }
}
