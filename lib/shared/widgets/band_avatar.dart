import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import '../../features/auth/data/models/band_summary.dart';

/// A circular band/user avatar with a colored fallback for null images.
///
/// - `BandAvatar.forBand` renders a [BandSummary]'s logo, falling back to the
///   first letter of the band's name on a tinted blue circle.
/// - `BandAvatar.forUser` renders a user's avatar with the same fallback
///   behavior. The auth lookup happens in the caller (this widget is not a
///   `ConsumerWidget`).
class BandAvatar extends StatelessWidget {
  const BandAvatar.forBand({
    super.key,
    required this.band,
    this.size = 18,
  })  : _imageUrl = null,
        _name = null;

  const BandAvatar.forUser({
    super.key,
    required String? imageUrl,
    required String name,
    this.size = 18,
  })  : band = null,
        _imageUrl = imageUrl,
        _name = name;

  final BandSummary? band;
  final String? _imageUrl;
  final String? _name;

  /// Avatar diameter in logical pixels.
  final double size;

  String get _resolvedImageUrl => band?.logoUrl ?? _imageUrl ?? '';
  String get _resolvedName => band?.name ?? _name ?? '';

  static String _initial(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return trimmed.substring(0, 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final fallbackBg = CupertinoColors.systemBlue
        .resolveFrom(context)
        .withValues(alpha: 0.15);
    final fallbackFg = CupertinoColors.systemBlue.resolveFrom(context);

    final imageUrl = _resolvedImageUrl;
    final name = _resolvedName;

    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fallbackBg,
      ),
      child: imageUrl.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: imageUrl,
              fit: BoxFit.cover,
              placeholder: (_, __) => const SizedBox.shrink(),
              errorWidget: (_, __, ___) => Center(
                child: Text(
                  _initial(name),
                  style: TextStyle(
                    fontSize: size * 0.55,
                    fontWeight: FontWeight.w600,
                    color: fallbackFg,
                  ),
                ),
              ),
            )
          : Center(
              child: Text(
                _initial(name),
                style: TextStyle(
                  fontSize: size * 0.55,
                  fontWeight: FontWeight.w600,
                  color: fallbackFg,
                ),
              ),
            ),
    );
  }
}
