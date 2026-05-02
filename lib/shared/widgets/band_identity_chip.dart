import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/auth/data/models/band_summary.dart';
import '../../features/auth/providers/auth_provider.dart';
import 'band_avatar.dart';

/// A horizontal `[avatar] [label]` row identifying a band — or, for personal
/// bands, the authenticated user.
///
/// Used on Dashboard cards, Bookings tab cards, and the booking-detail
/// header. Personal bands always render the user's avatar + the literal
/// label "Personal" (the band wrapper is hidden from the user).
class BandIdentityChip extends ConsumerWidget {
  const BandIdentityChip({
    super.key,
    required this.band,
    this.size = 18,
    this.textStyle,
  });

  final BandSummary band;

  /// Avatar diameter in logical pixels. Default is compact for cards.
  final double size;

  /// Optional text style override for the label.
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (band.isPersonal) {
      final auth = ref.watch(authProvider).value;
      final user = (auth is AuthAuthenticated) ? auth.user : null;
      return _ChipRow(
        avatar: BandAvatar.forUser(
          imageUrl: user?.avatarUrl,
          name: user?.name ?? 'You',
          size: size,
        ),
        label: 'Personal',
        textStyle: textStyle,
      );
    }
    return _ChipRow(
      avatar: BandAvatar.forBand(band: band, size: size),
      label: band.name,
      textStyle: textStyle,
    );
  }
}

class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.avatar, required this.label, this.textStyle});
  final Widget avatar;
  final String label;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        avatar,
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textStyle ??
                TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
                ),
          ),
        ),
      ],
    );
  }
}
