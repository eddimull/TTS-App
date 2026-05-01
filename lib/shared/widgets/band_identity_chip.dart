import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/auth/data/models/band_summary.dart';
import '../../features/auth/providers/auth_provider.dart';

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
        avatar: _Avatar(
          imageUrl: user?.avatarUrl,
          fallbackInitial: _initial(user?.name ?? 'You'),
          size: size,
        ),
        label: 'Personal',
        textStyle: textStyle,
      );
    }
    return _ChipRow(
      avatar: _Avatar(
        imageUrl: band.logoUrl,
        fallbackInitial: _initial(band.name),
        size: size,
      ),
      label: band.name,
      textStyle: textStyle,
    );
  }

  static String _initial(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return trimmed.substring(0, 1).toUpperCase();
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

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.imageUrl,
    required this.fallbackInitial,
    required this.size,
  });

  final String? imageUrl;
  final String fallbackInitial;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: CupertinoColors.systemBlue
            .resolveFrom(context)
            .withValues(alpha: 0.15),
        image: imageUrl != null
            ? DecorationImage(
                image: NetworkImage(imageUrl!),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: imageUrl != null
          ? null
          : Center(
              child: Text(
                fallbackInitial,
                style: TextStyle(
                  fontSize: size * 0.55,
                  fontWeight: FontWeight.w600,
                  color: CupertinoColors.systemBlue.resolveFrom(context),
                ),
              ),
            ),
    );
  }
}
