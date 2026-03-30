import 'package:flutter/cupertino.dart';

/// Small badge displayed next to a timeline entry time that falls after midnight.
class NextDayBadge extends StatelessWidget {
  const NextDayBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: CupertinoColors.systemOrange.resolveFrom(context).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '+1',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: CupertinoColors.systemOrange.resolveFrom(context),
        ),
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = switch (status.toLowerCase()) {
      'confirmed' => (
          'Confirmed',
          CupertinoColors.systemGreen.resolveFrom(context).withValues(alpha: 0.15),
          CupertinoColors.systemGreen.resolveFrom(context),
        ),
      'pending' => (
          'Pending',
          CupertinoColors.systemOrange.resolveFrom(context).withValues(alpha: 0.15),
          CupertinoColors.systemOrange.resolveFrom(context),
        ),
      'cancelled' || 'canceled' => (
          'Cancelled',
          CupertinoColors.systemRed.resolveFrom(context).withValues(alpha: 0.15),
          CupertinoColors.systemRed.resolveFrom(context),
        ),
      _ => (
          status,
          CupertinoColors.systemGrey5.resolveFrom(context),
          CupertinoColors.systemGrey.resolveFrom(context),
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Text(label,
          style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}
