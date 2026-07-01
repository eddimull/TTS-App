import 'planner_plan.dart';

/// Renders a single plan item as a `• <title> — <reason>` bullet line. An item
/// with an empty (or whitespace-only) reason renders as just `• <title>` (no
/// trailing dash). Shared by [formatPlanAsNotes] and the on-screen plan card so
/// the saved text and the live preview never diverge.
String formatPlanItemBullet(PlannerPlanItem item) {
  final reason = item.reason.trim();
  return reason.isEmpty ? '• ${item.title}' : '• ${item.title} — $reason';
}

/// Renders a [PlannerPlan] as plain text suitable for a rehearsal's notes field.
///
/// Layout: the title, a blank line, then one bullet per item (see
/// [formatPlanItemBullet]). A plan with no items renders as just the title line.
String formatPlanAsNotes(PlannerPlan plan) {
  if (plan.items.isEmpty) return plan.title;
  final bullets = plan.items.map(formatPlanItemBullet).join('\n');
  return '${plan.title}\n\n$bullets';
}
