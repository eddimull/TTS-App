import 'package:tts_bandmate/features/finances/providers/finances_provider.dart';
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
    final overdueCount = ref.watch(selectedBandOverdueCountProvider);

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
            semanticLabel:
                overdueCount > 0 ? 'Finances, $overdueCount overdue' : null,
            trailing: overdueCount > 0 ? _OverduePill(count: overdueCount) : null,
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
          if (isOwner)
            NavRow(
              title: 'Price Estimator',
              leading: Icon(CupertinoIcons.tag,
                  size: 22, color: context.secondaryText),
              onTap: () => context.push('/price-estimator'),
            ),
          NavRow(
            title: 'Lodging',
            leading: Icon(CupertinoIcons.bed_double,
                size: 22, color: context.secondaryText),
            onTap: () => context.push('/lodging'),
          ),
          NavRow(
            title: 'Media',
            leading: Icon(CupertinoIcons.photo_on_rectangle,
                size: 22, color: context.secondaryText),
            onTap: () => context.push('/media'),
          ),
          NavRow(
            title: 'Questionnaires',
            leading: Icon(CupertinoIcons.doc_text,
                size: 22, color: context.secondaryText),
            onTap: () => context.push('/questionnaires'),
          ),
        ],
      ),
    );
  }
}

class _OverduePill extends StatelessWidget {
  const _OverduePill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final red = CupertinoColors.systemRed.resolveFrom(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: red.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Text(
        '$count overdue',
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: red),
      ),
    );
  }
}
