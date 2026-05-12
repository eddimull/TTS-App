import 'package:flutter/cupertino.dart';

/// Cupertino-styled banner shown only on the all-failure save path.
/// Tap-to-dismiss returns control to the user without changing form state.
class BookingFormPartialFailureBanner extends StatelessWidget {
  const BookingFormPartialFailureBanner({
    super.key,
    required this.onDismiss,
  });

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onDismiss,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        color: CupertinoColors.destructiveRed.withValues(alpha: 0.12),
        child: const Row(
          children: [
            Icon(
              CupertinoIcons.exclamationmark_triangle_fill,
              color: CupertinoColors.destructiveRed,
              size: 18,
            ),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'No changes saved — check your connection',
                style: TextStyle(color: CupertinoColors.destructiveRed),
              ),
            ),
            Icon(
              CupertinoIcons.xmark,
              color: CupertinoColors.destructiveRed,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}
