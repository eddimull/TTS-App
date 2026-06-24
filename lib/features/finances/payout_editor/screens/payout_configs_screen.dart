import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';
import 'package:tts_bandmate/shared/widgets/empty_state_view.dart';
import 'package:tts_bandmate/shared/widgets/error_view.dart';

import '../providers/payout_flow_provider.dart';

/// Lists a band's payout configs; tapping one opens the flow editor.
class PayoutConfigsScreen extends ConsumerWidget {
  const PayoutConfigsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bandAsync = ref.watch(selectedBandProvider);

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('Payout Flow')),
      child: bandAsync.when(
        loading: () => const Center(child: CupertinoActivityIndicator()),
        error: (e, _) => ErrorView(message: ErrorView.friendlyMessage(e)),
        data: (bandId) {
          if (bandId == null) {
            return const ErrorView(message: 'No band selected.');
          }
          return _ConfigsList(bandId: bandId);
        },
      ),
    );
  }
}

class _ConfigsList extends ConsumerWidget {
  const _ConfigsList({required this.bandId});
  final int bandId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configsAsync = ref.watch(payoutConfigsProvider(bandId));
    final isOwner = ref.watch(isSelectedBandOwnerProvider);

    return configsAsync.when(
      loading: () => const Center(child: CupertinoActivityIndicator()),
      error: (e, _) => ErrorView(
        message: ErrorView.friendlyMessage(e),
        onRetry: () => ref.read(payoutConfigsProvider(bandId).notifier).refresh(),
      ),
      data: (configs) {
        if (configs.isEmpty) {
          return const EmptyStateView(
            icon: CupertinoIcons.money_dollar_circle,
            title: 'No payout configs',
            subtitle: 'Payout flow configurations for this band will appear here.',
          );
        }
        return CupertinoScrollbar(
          child: ListView.separated(
            itemCount: configs.length,
            separatorBuilder: (_, __) => Container(
              height: 0.5,
              margin: const EdgeInsets.only(left: 16),
              color: CupertinoColors.separator,
            ),
            itemBuilder: (context, i) {
              final c = configs[i];
              return CupertinoListTile(
                title: Text(c.name),
                subtitle: isOwner ? null : const Text('View only'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (c.isActive) const _ActiveBadge(),
                    const SizedBox(width: 6),
                    const CupertinoListTileChevron(),
                  ],
                ),
                onTap: () => context.push(
                  '/finances/payout-flow/$bandId/${c.id}',
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _ActiveBadge extends StatelessWidget {
  const _ActiveBadge();
  @override
  Widget build(BuildContext context) {
    final green = CupertinoColors.systemGreen.resolveFrom(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: green.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text('Active',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: green)),
    );
  }
}
