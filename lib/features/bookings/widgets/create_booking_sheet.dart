import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/providers/personal_band_provider.dart';
import '../../../shared/widgets/band_identity_chip.dart';
import '../../auth/data/models/band_summary.dart';
import '../../auth/providers/auth_provider.dart';

/// A sheet shown when the user taps "+" to create a new booking.
///
/// Real bands are listed at the top; tapping one invokes [onBandSelected]
/// with that band's id. A "Personal gig" row at the bottom creates the
/// personal band lazily (via `POST /bands/solo`) on first use, then invokes
/// [onBandSelected] with the personal band's id.
///
/// Callers are responsible for dismissing the sheet and navigating to the
/// booking form after [onBandSelected] fires.
class CreateBookingSheet extends ConsumerStatefulWidget {
  const CreateBookingSheet({super.key, required this.onBandSelected});

  /// Invoked with the chosen band id. The caller is responsible for
  /// dismissing the sheet and navigating to the booking form.
  final void Function(int bandId) onBandSelected;

  @override
  ConsumerState<CreateBookingSheet> createState() => _CreateBookingSheetState();
}

class _CreateBookingSheetState extends ConsumerState<CreateBookingSheet> {
  bool _personalLoading = false;
  String? _personalError;

  Future<void> _onPersonalTap() async {
    setState(() {
      _personalLoading = true;
      _personalError = null;
    });
    try {
      final personal =
          await ref.read(personalBandProvider.notifier).ensureExists();
      if (!mounted) return;
      widget.onBandSelected(personal.id);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _personalError = "Couldn't set up personal gigs. Try again.";
      });
    } finally {
      if (mounted) setState(() => _personalLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider).value;
    // Only expose non-personal bands in the list — the personal band is hidden
    // from the user; they select it indirectly via the "Personal gig" row.
    final bands = (auth is AuthAuthenticated)
        ? auth.bands.where((b) => !b.isPersonal).toList()
        : <BandSummary>[];

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: CupertinoColors.systemBackground.resolveFrom(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Grab handle — visually signals this is a bottom sheet
            const _GrabHandle(),
            const SizedBox(height: 8),
            if (bands.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Text(
                  'Create booking for',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
                ),
              ),
              for (final band in bands)
                _BandRow(
                  band: band,
                  onTap: () => widget.onBandSelected(band.id),
                ),
              // Thin separator between real bands and the personal row
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Container(
                  height: 0.5,
                  color: CupertinoColors.separator.resolveFrom(context),
                ),
              ),
            ],
            _PersonalRow(
              loading: _personalLoading,
              onTap: _personalLoading ? null : _onPersonalTap,
            ),
            if (_personalError != null) ...[
              const SizedBox(height: 8),
              Text(
                _personalError!,
                style: TextStyle(
                  fontSize: 13,
                  color: CupertinoColors.systemRed.resolveFrom(context),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Private sub-widgets ──────────────────────────────────────────────────────

class _GrabHandle extends StatelessWidget {
  const _GrabHandle();

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: CupertinoColors.systemGrey3.resolveFrom(context),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
}

class _BandRow extends StatelessWidget {
  const _BandRow({required this.band, required this.onTap});

  final BandSummary band;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        child: Row(
          children: [
            // BandIdentityChip handles avatar + band name in a single row widget
            BandIdentityChip(
              band: band,
              size: 28,
              textStyle: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: CupertinoColors.label.resolveFrom(context),
              ),
            ),
            const Spacer(),
            Icon(
              CupertinoIcons.chevron_right,
              size: 16,
              color: CupertinoColors.tertiaryLabel.resolveFrom(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _PersonalRow extends StatelessWidget {
  const _PersonalRow({required this.loading, required this.onTap});

  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        child: Row(
          children: [
            // Person icon stands in for the user's avatar — distinct from
            // the circular band-logo avatars above so this row reads as
            // a different "category" visually.
            Icon(
              CupertinoIcons.person_crop_circle_fill,
              size: 28,
              color: CupertinoColors.systemBlue.resolveFrom(context),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Personal gig',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: CupertinoColors.label.resolveFrom(context),
                    ),
                  ),
                  Text(
                    'Just for me, not tied to a band',
                    style: TextStyle(
                      fontSize: 12,
                      color: CupertinoColors.secondaryLabel.resolveFrom(context),
                    ),
                  ),
                ],
              ),
            ),
            // Swap chevron for spinner while personal band is being created
            if (loading)
              const CupertinoActivityIndicator(radius: 9)
            else
              Icon(
                CupertinoIcons.chevron_right,
                size: 16,
                color: CupertinoColors.tertiaryLabel.resolveFrom(context),
              ),
          ],
        ),
      ),
    );
  }
}
