import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../features/auth/data/models/band_summary.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/providers/selected_band_provider.dart';
import '../../../shared/widgets/nav_row.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';

/// Run-the-band surfaces, opened from the Dashboard hamburger.
class OperationsScreen extends ConsumerWidget {
  const OperationsScreen({super.key});

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

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('Operations')),
      child: ListView(
        children: [
          const SizedBox(height: 16),
          NavRow(
            title: 'Bookings',
            leading: Icon(CupertinoIcons.book,
                size: 22, color: context.secondaryText),
            onTap: () => context.push('/bookings'),
          ),
          NavRow(
            title: 'Finances',
            leading: Icon(CupertinoIcons.money_dollar_circle,
                size: 22, color: context.secondaryText),
            onTap: () => context.push('/finances'),
          ),
          NavRow(
            title: 'Rehearsals',
            leading: Icon(CupertinoIcons.person_2,
                size: 22, color: context.secondaryText),
            onTap: () => context.push('/rehearsals'),
          ),
          NavRow(
            title: 'Song list',
            leading: Icon(CupertinoIcons.music_note_2,
                size: 22, color: context.secondaryText),
            onTap: () => context.push('/songs'),
          ),
          if (isOwner)
            NavRow(
              title: 'Personnel',
              leading: Icon(CupertinoIcons.person_2_fill,
                  size: 22, color: context.secondaryText),
              onTap: () => context.push('/personnel'),
            ),
          NavRow(
            title: 'Media',
            leading: Icon(CupertinoIcons.photo_on_rectangle,
                size: 22, color: context.secondaryText),
            onTap: () => context.push('/media'),
          ),
        ],
      ),
    );
  }
}
