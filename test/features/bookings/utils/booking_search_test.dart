import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_contact.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_summary.dart';
import 'package:tts_bandmate/features/bookings/utils/booking_search.dart';

BookingSummary _booking({
  String name = 'Acme Wedding',
  String? venueName,
  List<BookingContact> contacts = const [],
}) =>
    BookingSummary(
      id: 1,
      name: name,
      date: '2026-06-01',
      venueName: venueName,
      isPaid: false,
      contacts: contacts,
    );

void main() {
  group('bookingMatchesQuery', () {
    test('empty query matches', () {
      expect(bookingMatchesQuery(_booking(), ''), true);
    });

    test('whitespace-only query matches', () {
      expect(bookingMatchesQuery(_booking(), '   '), true);
    });

    test('matches booking name (case-insensitive)', () {
      expect(bookingMatchesQuery(_booking(name: 'Acme Wedding'), 'acme'),
          true);
      expect(bookingMatchesQuery(_booking(name: 'Acme Wedding'), 'WED'),
          true);
    });

    test('matches venue name', () {
      final b = _booking(venueName: 'The Blue Note');
      expect(bookingMatchesQuery(b, 'blue'), true);
    });

    test('matches contact name', () {
      final b = _booking(contacts: const [
        BookingContact(id: 1, name: 'Alice Johnson'),
      ]);
      expect(bookingMatchesQuery(b, 'johnson'), true);
    });

    test('matches contact email', () {
      final b = _booking(contacts: const [
        BookingContact(id: 1, name: 'Alice', email: 'alice@example.com'),
      ]);
      expect(bookingMatchesQuery(b, 'example.com'), true);
    });

    test('matches contact phone', () {
      final b = _booking(contacts: const [
        BookingContact(id: 1, name: 'Alice', phone: '555-1234'),
      ]);
      expect(bookingMatchesQuery(b, '555'), true);
    });

    test('returns false when nothing matches', () {
      final b = _booking(
        name: 'Acme Wedding',
        venueName: 'The Blue Note',
        contacts: const [BookingContact(id: 1, name: 'Alice')],
      );
      expect(bookingMatchesQuery(b, 'zzzz'), false);
    });

    test('null fields do not throw', () {
      final b = _booking(); // venueName null, contacts empty
      expect(bookingMatchesQuery(b, 'anything'), false);
    });
  });
}
