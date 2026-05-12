import 'package:flutter/cupertino.dart';
import '../services/booking_save_orchestrator.dart';

class BookingFormNavigationGuard {
  /// Returns true when the user may leave (no pending failures, or they
  /// explicitly tapped Discard). Returns false when the user elected to
  /// stay (caller should NOT pop).
  ///
  /// When [result] is null or has no failures, returns true synchronously.
  static Future<bool> shouldAllowLeave(
    BuildContext context,
    BookingSaveResult? result,
  ) async {
    if (result == null || result.failedCount == 0) return true;

    final savedCount = _countSuccesses(result);
    final failedCount = result.failedCount;

    final outcome = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Unsaved changes'),
        content: Text(
          '$savedCount ${savedCount == 1 ? 'change' : 'changes'} saved, '
          '$failedCount still failed. Leave anyway?',
        ),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Discard'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Stay & Retry'),
          ),
        ],
      ),
    );
    return outcome ?? false;
  }

  static int _countSuccesses(BookingSaveResult r) {
    var n = 0;
    if (r.bookingPatch is OperationSuccess) n++;
    n += r.eventUpdates.values.whereType<OperationSuccess>().length;
    n += r.eventCreates.values.whereType<OperationSuccess>().length;
    n += r.eventDeletes.values.whereType<OperationSuccess>().length;
    return n;
  }
}
