// test/features/rehearsal_planner/models/planner_plan_formatter_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/rehearsal_planner/data/models/planner_plan.dart';
import 'package:tts_bandmate/features/rehearsal_planner/data/models/planner_plan_formatter.dart';

void main() {
  test('formats title, blank line, then one bullet per item', () {
    final plan = const PlannerPlan(
      title: 'Rehearsal plan — Smith Wedding',
      items: [
        PlannerPlanItem(title: 'At Last', reason: 'On the setlist, not rehearsed recently.'),
        PlannerPlanItem(title: 'Fly Me to the Moon', reason: 'Requested for the reception.'),
      ],
    );
    expect(
      formatPlanAsNotes(plan),
      'Rehearsal plan — Smith Wedding\n\n'
      '• At Last — On the setlist, not rehearsed recently.\n'
      '• Fly Me to the Moon — Requested for the reception.',
    );
  });

  test('item with empty reason has no trailing dash', () {
    final plan = const PlannerPlan(
      title: 'Plan',
      items: [PlannerPlanItem(title: 'Song A', reason: '')],
    );
    expect(formatPlanAsNotes(plan), 'Plan\n\n• Song A');
  });

  test('empty items returns just the title line', () {
    final plan = const PlannerPlan(title: 'Empty plan', items: []);
    expect(formatPlanAsNotes(plan), 'Empty plan');
  });

  group('formatPlanItemBullet', () {
    test('renders title and reason with a dash', () {
      const item = PlannerPlanItem(title: 'At Last', reason: 'On the setlist.');
      expect(formatPlanItemBullet(item), '• At Last — On the setlist.');
    });

    test('drops the dash when the reason is empty or whitespace', () {
      expect(formatPlanItemBullet(const PlannerPlanItem(title: 'Song A', reason: '')),
          '• Song A');
      expect(formatPlanItemBullet(const PlannerPlanItem(title: 'Song B', reason: '   ')),
          '• Song B');
    });
  });
}
