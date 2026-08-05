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

/// Returns the (label, background, foreground) style triple for a status
/// value, shared by [StatusChip] and any other status indicator (e.g. the
/// event-detail nav bar's status dot).
(String, Color, Color) _statusStyle(BuildContext context, String status) {
  return switch (status.toLowerCase()) {
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
}

/// The foreground/accent color for a status value (e.g. for a status dot).
/// Mirrors [StatusChip]'s color mapping.
Color statusColor(BuildContext context, String status) =>
    _statusStyle(context, status).$3;

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = _statusStyle(context, status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Text(label,
          style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}
