import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/rehearsals/data/models/rehearsal_detail.dart';
import 'package:tts_bandmate/features/rehearsals/data/models/rehearsal_schedule.dart';
import 'package:tts_bandmate/features/rehearsals/data/models/rehearsal_sub.dart';
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

  group('RehearsalSub', () {
    test('parses full payload', () {
      final sub = RehearsalSub.fromJson(const {
        'id': 5,
        'name': 'Pat Horn',
        'email': 'pat@example.com',
        'phone': '555-0100',
        'band_role_id': 3,
        'role_name': 'Trumpet',
        'user_id': 9,
        'is_registered': true,
      });

      expect(sub.id, 5);
      expect(sub.name, 'Pat Horn');
      expect(sub.roleName, 'Trumpet');
      expect(sub.isRegistered, isTrue);
    });

    test('handles nulls for ad-hoc invitee', () {
      final sub = RehearsalSub.fromJson(const {
        'id': 6,
        'name': 'Ad Hoc',
        'email': 'adhoc@example.com',
        'phone': null,
        'band_role_id': null,
        'role_name': null,
        'user_id': null,
        'is_registered': false,
      });

      expect(sub.isRegistered, isFalse);
      expect(sub.bandRoleId, isNull);
    });
  });

  group('RehearsalDetail subs', () {
    test('parses subs list and defaults to empty when absent', () {
      final withSubs = RehearsalDetail.fromJson(const {
        'id': 1,
        'is_cancelled': false,
        'schedule': {'id': 2, 'name': 'Weekly'},
        'subs': [
          {'id': 5, 'name': 'Pat', 'email': 'p@x.com', 'user_id': null},
        ],
      });
      expect(withSubs.subs, hasLength(1));
      expect(withSubs.subs.first.name, 'Pat');

      final withoutSubs = RehearsalDetail.fromJson(const {
        'id': 1,
        'is_cancelled': false,
        'schedule': {'id': 2, 'name': 'Weekly'},
      });
      expect(withoutSubs.subs, isEmpty);
    });
  });
}
