import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/models/calendar_feed.dart';
import '../providers/calendar_feed_provider.dart';

/// Lets the user subscribe their personal Google/Apple Calendar to the band
/// events they're entitled to. The feed stays auto-updated by the calendar
/// app; this screen just hands over the subscription URLs.
class CalendarFeedScreen extends ConsumerWidget {
  const CalendarFeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedAsync = ref.watch(calendarFeedProvider);

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Add to Calendar'),
      ),
      child: SafeArea(
        child: feedAsync.when(
          loading: () => const Center(child: CupertinoActivityIndicator()),
          error: (_, __) => _ErrorState(
            onRetry: () => ref.invalidate(calendarFeedProvider),
          ),
          data: (feed) => _FeedContent(feed: feed),
        ),
      ),
    );
  }
}

class _FeedContent extends ConsumerWidget {
  const _FeedContent({required this.feed});

  final CalendarFeed feed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Icon(
          CupertinoIcons.calendar_badge_plus,
          size: 56,
          color: CupertinoColors.activeBlue.resolveFrom(context),
        ),
        const SizedBox(height: 16),
        Text(
          'Subscribe to your events',
          textAlign: TextAlign.center,
          style: CupertinoTheme.of(context)
              .textTheme
              .navLargeTitleTextStyle
              .copyWith(fontSize: 24),
        ),
        const SizedBox(height: 12),
        Text(
          'Add your band events to your calendar. Your calendar app keeps them '
          'up to date automatically as gigs and rehearsals change.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            color: CupertinoColors.secondaryLabel.resolveFrom(context),
          ),
        ),
        const SizedBox(height: 28),
        CupertinoButton.filled(
          onPressed: () => _openUrl(context, feed.googleSubscribeUrl),
          child: const Text('Add to Google Calendar'),
        ),
        const SizedBox(height: 12),
        CupertinoButton(
          onPressed: () => _openUrl(context, feed.webcalUrl),
          child: const Text('Add to Apple Calendar'),
        ),
        const SizedBox(height: 4),
        CupertinoButton(
          onPressed: () => _copyLink(context),
          child: const Text('Copy feed link'),
        ),
        const SizedBox(height: 28),
        _ResetRow(
          onReset: () => _confirmReset(context, ref),
        ),
      ],
    );
  }

  Future<void> _openUrl(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (context.mounted) {
      _showMessage(
        context,
        "Couldn't open calendar",
        'Try "Copy feed link" and add it in your calendar app manually.',
      );
    }
  }

  Future<void> _copyLink(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: feed.url));
    if (context.mounted) {
      _showMessage(
        context,
        'Link copied',
        'Paste it into your calendar app to subscribe.',
      );
    }
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Reset feed link?'),
        content: const Text(
          'Your old link will stop working. Anyone you shared it with will need '
          'the new one.',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // reset() adopts the rotated URLs from the reset response directly, so no
    // extra GET is needed. It captures any failure into the provider's error
    // state, which the screen already renders.
    await ref.read(calendarFeedProvider.notifier).reset();
  }
}

class _ResetRow extends StatelessWidget {
  const _ResetRow({required this.onReset});

  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'Shared the wrong link or want to revoke access?',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: CupertinoColors.tertiaryLabel.resolveFrom(context),
          ),
        ),
        CupertinoButton(
          onPressed: onReset,
          child: Text(
            'Reset feed link',
            style: TextStyle(
              color: CupertinoColors.destructiveRed.resolveFrom(context),
            ),
          ),
        ),
      ],
    );
  }
}

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
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
            const SizedBox(height: 12),
            Text(
              "Couldn't load your calendar link.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
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

void _showMessage(BuildContext context, String title, String body) {
  showCupertinoDialog<void>(
    context: context,
    builder: (ctx) => CupertinoAlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
