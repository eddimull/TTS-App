import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../data/models/band_summary.dart';
import '../../../shared/providers/selected_band_provider.dart';

class BandSelectorScreen extends ConsumerWidget {
  const BandSelectorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authAsync = ref.watch(authProvider);
    final theme = Theme.of(context);

    return PopScope(
      // Prevent the user from backing out of band selection — it is required.
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Select Band'),
          automaticallyImplyLeading: false,
          actions: [
            TextButton.icon(
              onPressed: () async {
                await ref.read(authProvider.notifier).logout();
                // Router redirect will send to /login after logout.
              },
              icon: const Icon(Icons.logout),
              label: const Text('Sign out'),
            ),
          ],
        ),
        body: authAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(child: Text('Error: $err')),
          data: (authState) {
            if (authState is! AuthAuthenticated) {
              return const Center(child: Text('Not authenticated.'));
            }

            final bands = authState.bands;

            if (bands.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.group_off_outlined,
                      size: 48,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 16),
                    const Text('No bands found for your account.'),
                  ],
                ),
              );
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
    BuildContext context,
    WidgetRef ref,
    BandSummary band,
  ) async {
    await ref.read(selectedBandProvider.notifier).selectBand(band.id);
    // Router redirect observes selectedBandProvider and will navigate to
    // /dashboard automatically — no explicit context.go() needed.
  }
}

class _BandTile extends StatelessWidget {
  const _BandTile({required this.band, required this.onTap});

  final BandSummary band;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Text(
            band.name.isNotEmpty ? band.name[0].toUpperCase() : '?',
            style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
          ),
        ),
        title: Text(
          band.name,
          style: theme.textTheme.titleMedium,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (band.isOwner)
              Chip(
                label: const Text('Owner'),
                labelStyle: TextStyle(
                  color: theme.colorScheme.onSecondaryContainer,
                  fontSize: 12,
                ),
                backgroundColor: theme.colorScheme.secondaryContainer,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
              ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}
