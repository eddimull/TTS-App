import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/models/band_summary.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../shared/widgets/band_avatar.dart';
import '../data/models/booking_status.dart';
import '../providers/bookings_filter_provider.dart';

/// Modal popup contents for filtering the Bookings list by status + band.
///
/// Lives inside `showCupertinoModalPopup`. Visually mirrors
/// `LibraryFilterSheet` with an added STATUS section above BANDS.
class BookingsFilterSheet extends ConsumerWidget {
  const BookingsFilterSheet({super.key, required this.bands});

  final List<BandSummary> bands;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(bookingsFilterProvider);
    final notifier = ref.read(bookingsFilterProvider.notifier);

    return Container(
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground.resolveFrom(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: const EdgeInsets.only(bottom: 12),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            _DragHandle(),
            const SizedBox(height: 8),
            _Header(
              isActive: filter.isActive,
              onClear: () {
                HapticFeedback.selectionClick();
                notifier.clear();
              },
            ),
            const SizedBox(height: 8),
            const _SectionLabel(label: 'STATUS'),
            const SizedBox(height: 8),
            _StatusPills(
              current: filter.status,
              onChanged: (s) {
                HapticFeedback.selectionClick();
                notifier.setStatus(s);
              },
            ),
            const SizedBox(height: 12),
            const _SectionLabel(label: 'BANDS'),
            const SizedBox(height: 8),
            _BandsRow(
              bands: bands,
              hiddenBandIds: filter.hiddenBandIds,
              onToggle: (id) {
                HapticFeedback.selectionClick();
                notifier.toggleBand(id);
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _DragHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: CupertinoColors.systemGrey4.resolveFrom(context),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.isActive, required this.onClear});
  final bool isActive;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Center(
            child: Text(
              'Filter',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
          ),
          if (isActive)
            Align(
              alignment: Alignment.centerRight,
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: onClear,
                child: Text(
                  'Clear All',
                  style: TextStyle(
                    color: CupertinoColors.systemRed.resolveFrom(context),
                    fontSize: 15,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
            color: CupertinoColors.secondaryLabel.resolveFrom(context),
          ),
        ),
      ),
    );
  }
}

class _StatusPills extends StatelessWidget {
  const _StatusPills({required this.current, required this.onChanged});

  final BookingStatus current;
  final ValueChanged<BookingStatus> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: BookingStatus.values.map((s) {
          final isSelected = current == s;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onChanged(s),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: isSelected
                      ? CupertinoColors.systemBlue.resolveFrom(context)
                      : CupertinoColors.tertiarySystemBackground
                          .resolveFrom(context),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  s.label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isSelected
                        ? CupertinoColors.white
                        : CupertinoColors.label.resolveFrom(context),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _BandsRow extends ConsumerWidget {
  const _BandsRow({
    required this.bands,
    required this.hiddenBandIds,
    required this.onToggle,
  });

  final List<BandSummary> bands;
  final Set<int> hiddenBandIds;
  final void Function(int bandId) onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider).value;
    final user = (auth is AuthAuthenticated) ? auth.user : null;
    return SizedBox(
      height: 80,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: bands.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final band = bands[i];
          final isVisible = !hiddenBandIds.contains(band.id);
          final isPersonal = band.isPersonal;
          final avatar = isPersonal
              ? BandAvatar.forUser(
                  imageUrl: user?.avatarUrl,
                  name: user?.name ?? 'You',
                  size: 36,
                )
              : BandAvatar.forBand(band: band, size: 36);
          final label = isPersonal ? 'Personal' : band.name;
          return GestureDetector(
            onTap: () => onToggle(band.id),
            behavior: HitTestBehavior.opaque,
            child: Semantics(
              label: label,
              selected: isVisible,
              button: true,
              child: SizedBox(
                width: 64,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Opacity(
                      opacity: isVisible ? 1.0 : 0.4,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isVisible
                                ? CupertinoColors.systemBlue
                                    .resolveFrom(context)
                                : CupertinoColors.systemGrey5
                                    .resolveFrom(context),
                            width: 2,
                          ),
                        ),
                        padding: const EdgeInsets.all(2),
                        child: avatar,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Opacity(
                      opacity: isVisible ? 1.0 : 0.4,
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
