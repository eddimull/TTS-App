import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_contact.dart';
import 'package:tts_bandmate/features/questionnaires/widgets/send_from_event.dart';

void main() {
  test('only contacts linked to a contact record can be sent to', () {
    final contacts = [
      BookingContact.fromJson({
        'id': 1,
        'name': 'Grace',
        'contact_id': 40,
        'is_primary': true,
        'can_login': true,
      }),
      BookingContact.fromJson({'id': 2, 'name': 'Planner'}),
    ];
    final eligible = eligibleContactsFrom(contacts);
    expect(eligible, hasLength(1));
    expect(eligible.single.id, 40);
    expect(eligible.single.name, 'Grace');
    expect(eligible.single.isPrimary, isTrue);
    expect(eligible.single.canLogin, isTrue);
  });
}
