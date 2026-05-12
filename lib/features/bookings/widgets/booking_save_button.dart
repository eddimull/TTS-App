import 'package:flutter/cupertino.dart';
import '../services/booking_save_orchestrator.dart';

/// The booking form's primary save action rendered in the navigation bar
/// trailing position. Two visual states:
/// - **pristine** (no prior result, or all-failure result): "Save Booking",
///   default active-blue tint.
/// - **partial-failure** (some ops succeeded, some failed): "Retry Failed
///   (N)", destructive red tint.
///
/// While [isSaving] is true the button shows a [CupertinoActivityIndicator]
/// in place of the text.
class BookingSaveButton extends StatelessWidget {
  const BookingSaveButton({
    super.key,
    required this.isSaving,
    required this.lastResult,
    required this.onPressed,
  });

  final bool isSaving;
  final BookingSaveResult? lastResult;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (isSaving) {
      return const CupertinoActivityIndicator();
    }
    final isPartial = lastResult?.partiallySucceeded == true;
    final label = isPartial
        ? 'Retry Failed (${lastResult!.failedCount})'
        : 'Save Booking';
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      child: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: isPartial
              ? CupertinoColors.destructiveRed
              : CupertinoColors.activeBlue,
        ),
      ),
    );
  }
}
