import 'planner_plan.dart';

/// Renders a [PlannerPlan] as plain text suitable for a rehearsal's notes field.
///
/// Layout: the title, a blank line, then one `• <title> — <reason>` bullet per
/// item. An item with an empty reason renders as just `• <title>` (no trailing
/// dash). A plan with no items renders as just the title line.
String formatPlanAsNotes(PlannerPlan plan) {
  if (plan.items.isEmpty) return plan.title;
  final bullets = plan.items.map((item) {
    final reason = item.reason.trim();
    return reason.isEmpty ? '• ${item.title}' : '• ${item.title} — $reason';
  }).join('\n');
  return '${plan.title}\n\n$bullets';
}
