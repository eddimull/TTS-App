import 'package:flutter/cupertino.dart';

/// Colored status pill for a questionnaire instance:
/// sent (blue) / in_progress (orange) / submitted (green) / locked (grey).
class InstanceStatusBadge extends StatelessWidget {
  const InstanceStatusBadge({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'sent' => ('Sent', CupertinoColors.systemBlue.resolveFrom(context)),
      'in_progress' => (
          'In progress',
          CupertinoColors.systemOrange.resolveFrom(context)
        ),
      'submitted' => (
          'Submitted',
          CupertinoColors.systemGreen.resolveFrom(context)
        ),
      'locked' => ('Locked', CupertinoColors.systemGrey.resolveFrom(context)),
      _ => (status, CupertinoColors.systemGrey.resolveFrom(context)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style:
            TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}
