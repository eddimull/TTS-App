import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/models/contract_history_entry.dart';

void main() {
  group('ContractHistoryEntry', () {
    test('parses all fields', () {
      final e = ContractHistoryEntry.fromJson({
        'id': 'evt-1',
        'created_at': '2026-05-11T12:00:00Z',
        'action': 'Document Sent',
        'action_code': 6,
        'user_email': 'a@b.com',
        'description': 'Sent to signer.',
        'reason': null,
        'status': 'completed',
        'ip_address': '1.2.3.4',
      });
      expect(e.id, 'evt-1');
      expect(e.action, 'Document Sent');
      expect(e.actionCode, 6);
      expect(e.userEmail, 'a@b.com');
      expect(e.status, 'completed');
      expect(e.ipAddress, '1.2.3.4');
      expect(e.reason, isNull);
    });

    test('safe defaults for nulls', () {
      final e = ContractHistoryEntry.fromJson({'id': 'x'});
      expect(e.id, 'x');
      expect(e.action, '');
      expect(e.actionCode, 0);
      expect(e.userEmail, '');
      expect(e.status, '');
    });
  });
}
