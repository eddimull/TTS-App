import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/providers/selected_band_provider.dart';
import '../providers/band_settings_provider.dart';
import 'band_info_edit_screen.dart';

class BandSettingsScreen extends ConsumerWidget {
  const BandSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bandId = ref.watch(selectedBandProvider).value;

    const navBar = CupertinoNavigationBar(middle: Text('Band Settings'));

    if (bandId == null) {
      return const CupertinoPageScaffold(
        navigationBar: navBar,
        child: SafeArea(
          child: Center(child: CupertinoActivityIndicator()),
        ),
      );
    }

    final settingsAsync = ref.watch(bandSettingsProvider(bandId));

    if (settingsAsync.isLoading && !settingsAsync.hasValue) {
      return const CupertinoPageScaffold(
        navigationBar: navBar,
        child: SafeArea(
          child: Center(child: CupertinoActivityIndicator()),
        ),
      );
    }

    if (settingsAsync.hasError && !settingsAsync.hasValue) {
      return const CupertinoPageScaffold(
        navigationBar: navBar,
        child: SafeArea(
          child: Center(
            child: Text(
              'Failed to load band settings. Please try again.',
              style: TextStyle(color: CupertinoColors.secondaryLabel),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final settings = settingsAsync.value!;

    return CupertinoPageScaffold(
      navigationBar: navBar,
      child: SafeArea(
        child: ListView(
          children: [
            // ── Band Info ─────────────────────────────────────────────────────
            CupertinoListSection.insetGrouped(
              header: const Text('Band Info'),
              children: [
                CupertinoListTile(
                  leading: _BandLogo(logoUrl: settings.detail.logoUrl),
                  title: Text(settings.detail.name),
                  subtitle: Text(settings.detail.siteName),
                  trailing: const CupertinoListTileChevron(),
                  onTap: () => Navigator.of(context).push(
                    CupertinoPageRoute<void>(
                      builder: (_) => BandInfoEditScreen(
                        bandId: bandId,
                        initial: settings.detail,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Band logo avatar ──────────────────────────────────────────────────────────

class _BandLogo extends StatelessWidget {
  const _BandLogo({required this.logoUrl});

  final String? logoUrl;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: Container(
        width: 36,
        height: 36,
        color: CupertinoColors.systemGrey5,
        child: logoUrl != null
            ? Image.network(
                logoUrl!,
                width: 36,
                height: 36,
                fit: BoxFit.cover,
              )
            : const Icon(
                CupertinoIcons.music_note,
                size: 16,
                color: CupertinoColors.systemGrey,
              ),
      ),
    );
  }
}
