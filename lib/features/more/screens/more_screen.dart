import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../features/auth/data/models/band_summary.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../features/chat/providers/conversations_provider.dart';
import '../../../shared/providers/selected_band_provider.dart';
import '../../../shared/widgets/nav_row.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider).value;
    final bandId = ref.watch(selectedBandProvider).value;

    final bands = authState is AuthAuthenticated
        ? authState.bands
        : const <BandSummary>[];
    final currentBand =
        bandId == null ? null : bands.where((b) => b.id == bandId).firstOrNull;
    final isOwner = currentBand?.isOwner ?? false;
    final unread = ref.watch(chatUnreadTotalProvider);

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('More')),
      child: ListView(
        children: [
          const SizedBox(height: 16),
          if (bands.length > 1)
            NavRow(
              title: 'Switch Band',
              subtitle: currentBand?.name,
              leading: Icon(
                CupertinoIcons.arrow_2_squarepath,
                size: 22,
                color: context.secondaryText,
              ),
              onTap: () => _showBandSwitcher(context, ref, bands, bandId),
            ),
          NavRow(
            title: 'Messages',
            subtitle: unread > 0 ? '$unread unread' : null,
            leading: Icon(
              CupertinoIcons.chat_bubble_2,
              size: 22,
              color: unread > 0
                  ? CupertinoColors.activeBlue.resolveFrom(context)
                  : context.secondaryText,
            ),
            onTap: () => context.push('/messages'),
          ),
          NavRow(
            title: 'Finances',
            leading: Icon(
              CupertinoIcons.money_dollar_circle,
              size: 22,
              color: context.secondaryText,
            ),
            onTap: () => context.push('/finances'),
          ),
          NavRow(
            title: 'Rehearsals',
            leading: Icon(
              CupertinoIcons.person_2,
              size: 22,
              color: context.secondaryText,
            ),
            onTap: () => context.push('/rehearsals'),
          ),
          NavRow(
            title: 'Media',
            leading: Icon(
              CupertinoIcons.photo_on_rectangle,
              size: 22,
              color: context.secondaryText,
            ),
            onTap: () => context.push('/media'),
          ),
          NavRow(
            title: 'My Stats',
            leading: Icon(
              CupertinoIcons.chart_bar_alt_fill,
              size: 22,
              color: context.secondaryText,
            ),
            onTap: () => context.push('/stats'),
          ),
          NavRow(
            title: 'Add to Calendar',
            leading: Icon(
              CupertinoIcons.calendar_badge_plus,
              size: 22,
              color: context.secondaryText,
            ),
            onTap: () => context.push('/calendar-feed'),
          ),
          if (isOwner) ...[
            NavRow(
              title: 'Personnel',
              leading: Icon(
                CupertinoIcons.person_2_fill,
                size: 22,
                color: context.secondaryText,
              ),
              onTap: () => context.push('/personnel'),
            ),
            NavRow(
              title: 'Band Settings',
              leading: Icon(
                CupertinoIcons.settings,
                size: 22,
                color: context.secondaryText,
              ),
              onTap: () => context.push('/band-settings'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showBandSwitcher(
    BuildContext context,
    WidgetRef ref,
    List<BandSummary> bands,
    int? currentBandId,
  ) async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: const Text('Switch Band'),
        actions: [
          for (final band in bands)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(sheetContext);
                if (band.id != currentBandId) {
                  ref.read(selectedBandProvider.notifier).selectBand(band.id);
                }
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (band.id == currentBandId) ...[
                    const Icon(CupertinoIcons.check_mark, size: 18),
                    const SizedBox(width: 6),
                  ],
                  Flexible(child: Text(band.name)),
                ],
              ),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetContext),
          child: const Text('Cancel'),
        ),
      ),
    );
  }
}
