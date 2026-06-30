import 'package:flutter/cupertino.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';

/// A tappable banner shown at the top of [EventDetailScreen] when the event
/// belongs to a booking.  Tapping navigates to that booking.
///
/// When [bookingName] is provided (the event was opened from its booking),
/// the banner reads "Part of: [bookingName]".  When it is null (the event was
/// opened directly and we only know it is booking-backed), the banner falls
/// back to a generic "Go to booking" label with a chevron.
class PartOfBookingRow extends StatelessWidget {
  const PartOfBookingRow({
    super.key,
    this.bookingName,
    required this.onTap,
  });

  final String? bookingName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasName = bookingName != null && bookingName!.isNotEmpty;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: CupertinoColors.systemGroupedBackground.resolveFrom(context),
        child: Row(
          children: [
            const Icon(
              CupertinoIcons.bookmark,
              size: 14,
              color: CupertinoColors.systemBlue,
            ),
            const SizedBox(width: 6),
            if (hasName) ...[
              Text(
                'Part of: ',
                style: TextStyle(
                  color: context.primaryText,
                ),
              ),
              Flexible(
                child: Text(
                  bookingName!,
                  style: const TextStyle(color: CupertinoColors.systemBlue),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ] else ...[
              const Expanded(
                child: Text(
                  'Go to booking',
                  style: TextStyle(color: CupertinoColors.systemBlue),
                ),
              ),
              const Icon(
                CupertinoIcons.chevron_right,
                size: 14,
                color: CupertinoColors.systemBlue,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
