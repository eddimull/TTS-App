import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../data/models/band_summary.dart';
import '../../../shared/providers/selected_band_provider.dart';
class BandSelectorScreen extends ConsumerWidget {
  const BandSelectorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authAsync = ref.watch(authProvider);

    return PopScope(
      canPop: false,
      child: CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          middle: const Text('Select Band'),
          automaticallyImplyLeading: false,
          trailing: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () async {
              await ref.read(authProvider.notifier).logout();
            },
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(CupertinoIcons.square_arrow_right, size: 18),
                SizedBox(width: 4),
                Text('Sign out'),
              ],
            ),
          ),
        ),
        child: authAsync.when(
          loading: () =>
              const Center(child: CupertinoActivityIndicator()),
          error: (err, _) => Center(child: Text('Error: $err')),
          data: (authState) {
            if (authState is! AuthAuthenticated) {
              return const Center(child: Text('Not authenticated.'));
            }

            final bands = authState.bands;

            if (bands.isEmpty) {
              // Router guard redirects to /bands which shows PathSelectionScreen.
              // This branch is a safety fallback only.
              return const Center(child: CupertinoActivityIndicator());
            }

            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: bands.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final band = bands[index];
                return _BandTile(
                  band: band,
                  onTap: () => _selectBand(context, ref, band),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _selectBand(
      BuildContext context, WidgetRef ref, BandSummary band) async {
    await ref.read(selectedBandProvider.notifier).selectBand(band.id);
  }
}

class _BandTile extends StatelessWidget {
  const _BandTile({required this.band, required this.onTap});

  final BandSummary band;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: CupertinoColors.systemBlue.resolveFrom(context).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  band.name.isNotEmpty ? band.name[0].toUpperCase() : '?',
                  style: TextStyle(
                    color: CupertinoColors.systemBlue.resolveFrom(context),
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                band.name,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w500),
              ),
            ),
            if (band.isOwner) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: CupertinoColors.systemBlue.resolveFrom(context).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Owner',
                  style: TextStyle(
                    color: CupertinoColors.systemBlue.resolveFrom(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Icon(CupertinoIcons.chevron_right,
                size: 18, color: CupertinoColors.tertiaryLabel.resolveFrom(context)),
          ],
        ),
      ),
    );
  }
}
