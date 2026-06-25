import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/finances/payout_editor/data/payout_flow_repository.dart';

void main() {
  group('PayoutTemplate.fromJson', () {
    test('maps key, name, description', () {
      final t = PayoutTemplate.fromJson(const {
        'key': 'equal_split',
        'name': 'Equal split',
        'description': 'Everyone splits evenly.',
      });
      expect(t.key, 'equal_split');
      expect(t.name, 'Equal split');
      expect(t.description, 'Everyone splits evenly.');
    });
  });
}
