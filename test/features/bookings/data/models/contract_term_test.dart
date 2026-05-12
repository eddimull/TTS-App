import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/models/contract_term.dart';

void main() {
  group('ContractTerm', () {
    test('fromJson parses title and content', () {
      final t = ContractTerm.fromJson({'title': 'A', 'content': 'B'});
      expect(t.title, 'A');
      expect(t.content, 'B');
    });

    test('fromJson defaults null fields to empty strings', () {
      final t = ContractTerm.fromJson({});
      expect(t.title, '');
      expect(t.content, '');
    });

    test('toJson emits only title and content', () {
      const t = ContractTerm(id: 5, title: 'T', content: 'C');
      expect(t.toJson(), {'title': 'T', 'content': 'C'});
    });

    test('copyWith preserves id and updates fields', () {
      const t = ContractTerm(id: 7, title: 'a', content: 'b');
      final u = t.copyWith(title: 'aa');
      expect(u.id, 7);
      expect(u.title, 'aa');
      expect(u.content, 'b');
    });
  });
}
