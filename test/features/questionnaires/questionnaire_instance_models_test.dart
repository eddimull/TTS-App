import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/questionnaires/data/models/eligible_booking.dart';
import 'package:tts_bandmate/features/questionnaires/data/models/questionnaire_instance.dart';

void main() {
  group('QuestionnaireInstance.fromJson', () {
    test('test_parses_summary_row', () {
      final i = QuestionnaireInstance.fromJson({
        'id': 7,
        'name': 'Wedding Intake',
        'status': 'in_progress',
        'sent_at': '2026-07-15T10:00:00+00:00',
        'submitted_at': null,
        'recipient_name': 'Alice',
        'booking': {'id': 3, 'name': 'Smith Wedding'},
        'questionnaire_id': 1,
      });
      expect(i.id, 7);
      expect(i.status, 'in_progress');
      expect(i.statusLabel, 'In progress');
      expect(i.recipientName, 'Alice');
      expect(i.bookingId, 3);
      expect(i.bookingName, 'Smith Wedding');
      expect(i.sentAt, isNotNull);
      expect(i.submittedAt, null);
      expect(i.fields, isEmpty);
      expect(i.isLocked, false);
    });

    test('test_parses_detail_with_responses_and_songs', () {
      final i = QuestionnaireInstance.fromJson({
        'id': 7,
        'name': 'Wedding Intake',
        'status': 'submitted',
        'recipient_name': 'Alice',
        'booking': {'id': 3, 'name': 'Smith Wedding'},
        'fields': [
          {'id': 21, 'type': 'short_text', 'label': 'Name', 'position': 10},
          {'id': 22, 'type': 'song_picker', 'label': 'Must play', 'position': 20},
        ],
        'responses': {
          '21': 'Alice',
          '22': [5, 9],
        },
        'song_lookup': {
          '5': {'title': 'Song A', 'artist': 'Artist A'},
          '9': {'title': '(removed song #9)', 'artist': null},
        },
      });
      expect(i.isSubmitted, true);
      expect(i.fields.length, 2);
      expect(i.responses['21'], 'Alice');
      expect(i.responses['22'], [5, 9]);
      expect(i.songLookup['5']!.display, 'Song A — Artist A');
      expect(i.songLookup['9']!.display, '(removed song #9)');
    });

    test('test_status_labels', () {
      for (final (status, label) in [
        ('sent', 'Sent'),
        ('in_progress', 'In progress'),
        ('submitted', 'Submitted'),
        ('locked', 'Locked'),
        ('weird', 'weird'),
      ]) {
        final i = QuestionnaireInstance.fromJson({
          'id': 1, 'name': 'x', 'status': status,
          'recipient_name': 'r', 'booking': {'id': 1, 'name': 'b'},
        });
        expect(i.statusLabel, label);
      }
    });
  });

  group('EligibleBooking.fromJson', () {
    test('test_parses_contacts_with_portal_flag', () {
      final b = EligibleBooking.fromJson({
        'id': 3,
        'name': 'Smith Wedding',
        'date': 'Oct 10, 2026',
        'already_sent': true,
        'contacts': [
          {'id': 1, 'name': 'Alice', 'is_primary': true, 'can_login': true},
          {'id': 2, 'name': 'Bob', 'is_primary': false, 'can_login': false},
        ],
      });
      expect(b.alreadySent, true);
      expect(b.contacts.first.canLogin, true);
      expect(b.contacts.last.canLogin, false);
    });
  });

  group('BookingQuestionnaires.fromJson', () {
    test('test_parses_instances_and_templates', () {
      final payload = BookingQuestionnaires.fromJson({
        'instances': [
          {'id': 7, 'name': 'Intake', 'status': 'sent',
           'recipient_name': 'Alice', 'booking': {'id': 3, 'name': 'b'}},
        ],
        'available_questionnaires': [
          {'id': 1, 'name': 'Wedding Intake'},
        ],
      });
      expect(payload.instances.single.id, 7);
      expect(payload.availableQuestionnaires.single.name, 'Wedding Intake');
    });
  });
}
