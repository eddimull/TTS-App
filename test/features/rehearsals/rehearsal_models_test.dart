import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/rehearsals/data/models/rehearsal_schedule.dart';
import 'package:tts_bandmate/features/rehearsals/data/models/rehearsal_summary.dart';

void main() {
  test('RehearsalSummary parses a virtual occurrence (null id)', () {
    final summary = RehearsalSummary.fromJson({
      'id': null,
      'date': '2026-08-05',
      'time': '19:00',
      'is_cancelled': false,
      'event_key': 'virtual-rehearsal-7-2026-08-05',
      'is_virtual': true,
    });

    expect(summary.id, isNull);
    expect(summary.isVirtual, isTrue);
    expect(summary.eventKey, 'virtual-rehearsal-7-2026-08-05');
  });

  test('RehearsalSummary defaults isVirtual to false for old payloads', () {
    final summary = RehearsalSummary.fromJson({
      'id': 42,
      'date': '2026-07-29',
      'is_cancelled': false,
    });

    expect(summary.id, 42);
    expect(summary.isVirtual, isFalse);
  });

  test('RehearsalSchedule parses recurrence_label and tolerates absence', () {
    final withLabel = RehearsalSchedule.fromJson({
      'id': 7,
      'name': 'Weekly',
      'active': true,
      'recurrence_label': 'Every Wednesday at 7:00 PM',
      'upcoming_rehearsals': [],
    });
    expect(withLabel.recurrenceLabel, 'Every Wednesday at 7:00 PM');

    final without = RehearsalSchedule.fromJson({
      'id': 8,
      'name': 'Old payload',
      'active': true,
      'upcoming_rehearsals': [],
    });
    expect(without.recurrenceLabel, isNull);
  });
}
