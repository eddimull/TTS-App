import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/events/data/models/event_detail.dart';
import 'package:tts_bandmate/features/events/data/models/event_member.dart';

void main() {
  group('EventDetail.fromJson', () {
    Map<String, dynamic> _fullJson({List<dynamic> members = const []}) => {
          'id': 1,
          'key': 'evt-key',
          'title': 'Wedding Reception',
          'date': '2026-05-20',
          'time': '18:30',
          'notes': 'Black tie required',
          'event_type': 'Wedding',
          'event_type_id': 3,
          'venue_name': 'Rosewood Manor',
          'venue_address': '456 Oak Ave',
          'status': 'confirmed',
          'eventable_type': 'Bookings',
          'eventable_id': 12,
          'can_write': true,
          'live_session_id': null,
          'members': members,
        };

    test('test_parses_full_event_detail', () {
      final detail = EventDetail.fromJson(_fullJson());

      expect(detail.id, 1);
      expect(detail.key, 'evt-key');
      expect(detail.title, 'Wedding Reception');
      expect(detail.date, '2026-05-20');
      expect(detail.time, '18:30');
      expect(detail.notes, 'Black tie required');
      expect(detail.eventType, 'Wedding');
      expect(detail.eventTypeId, 3);
      expect(detail.venueName, 'Rosewood Manor');
      expect(detail.status, 'confirmed');
      expect(detail.eventableType, 'Bookings');
      expect(detail.canWrite, isTrue);
      expect(detail.liveSessionId, isNull);
      expect(detail.members, isEmpty);
    });

    test('test_parses_members_list', () {
      final detail = EventDetail.fromJson(_fullJson(members: [
        {
          'id': 10,
          'user_id': 3,
          'name': 'John Smith',
          'attendance_status': 'confirmed',
          'role': 'Lead Singer',
        },
        {
          'id': 11,
          'user_id': null,
          'name': 'Sub Player',
          'attendance_status': 'pending',
          'role': null,
        },
      ]));

      expect(detail.members, hasLength(2));
      expect(detail.members[0].name, 'John Smith');
      expect(detail.members[0].attendanceStatus, 'confirmed');
      expect(detail.members[0].role, 'Lead Singer');
      expect(detail.members[1].userId, isNull);
      expect(detail.members[1].role, isNull);
    });

    test('test_parses_live_session_id_when_present', () {
      final json = _fullJson()..['live_session_id'] = 42;
      final detail = EventDetail.fromJson(json);
      expect(detail.liveSessionId, 42);
    });

    test('test_can_write_defaults_to_false_when_missing', () {
      final json = _fullJson()..remove('can_write');
      final detail = EventDetail.fromJson(json);
      expect(detail.canWrite, isFalse);
    });

    test('test_members_is_empty_list_when_key_missing', () {
      final json = _fullJson()..remove('members');
      final detail = EventDetail.fromJson(json);
      expect(detail.members, isEmpty);
    });

    test('test_parsed_date_returns_correct_datetime', () {
      final detail = EventDetail.fromJson(_fullJson());
      expect(detail.parsedDate, DateTime(2026, 5, 20));
    });
  });

  group('EventMember.fromJson', () {
    test('test_parses_full_member', () {
      final member = EventMember.fromJson({
        'id': 5,
        'user_id': 8,
        'name': 'Jane Doe',
        'attendance_status': 'absent',
        'role': 'Drums',
      });

      expect(member.id, 5);
      expect(member.userId, 8);
      expect(member.name, 'Jane Doe');
      expect(member.attendanceStatus, 'absent');
      expect(member.role, 'Drums');
    });

    test('test_parses_member_with_null_user_id_and_role', () {
      final member = EventMember.fromJson({
        'id': 6,
        'user_id': null,
        'name': 'Sub Bassist',
        'attendance_status': null,
        'role': null,
      });

      expect(member.userId, isNull);
      expect(member.role, isNull);
      expect(member.attendanceStatus, isNull);
    });
  });
}
