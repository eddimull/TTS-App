import 'package:flutter/cupertino.dart';

/// A tappable banner shown at the top of [EventDetailScreen] when the event
/// was opened from a booking detail.  Tapping navigates back to that booking.
class PartOfBookingRow extends StatelessWidget {
  const PartOfBookingRow({
    super.key,
    required this.bookingName,
    required this.onTap,
  });

  final String bookingName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
            Text(
              'Part of: ',
              style: TextStyle(
                color: CupertinoColors.label.resolveFrom(context),
              ),
            ),
            Flexible(
              child: Text(
                bookingName,
                style: const TextStyle(color: CupertinoColors.systemBlue),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
