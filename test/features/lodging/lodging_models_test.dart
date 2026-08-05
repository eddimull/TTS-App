import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/lodging/data/models/lodging.dart';

void main() {
  group('Lodging.fromJson', () {
    test('parses full payload', () {
      final json = {
        'id': 1,
        'name': 'Hampton Inn',
        'address': '123 Main St',
        'latitude': 30.4,
        'longitude': -91.1,
        'check_in_at': '2030-08-14 15:00:00',
        'check_out_at': '2030-08-16 11:00:00',
        'notes': 'Park in back',
        'booking': {'id': 5, 'name': 'Smith Wedding'},
        'event': {'id': 9, 'title': 'Reception', 'date': '2030-08-15'},
        'rooms': [
          {'id': 1, 'label': 'King', 'confirmation_number': 'ABC123', 'notes': null, 'sort_order': 0},
        ],
        'attachments': [
          {'id': 2, 'filename': 'map.jpg', 'mime_type': 'image/jpeg', 'file_size': 1234, 'url': 'https://x/api/mobile/lodging-attachments/2'},
        ],
      };

      final lodging = Lodging.fromJson(json);
      expect(lodging.id, 1);
      expect(lodging.name, 'Hampton Inn');
      expect(lodging.latitude, 30.4);
      expect(lodging.checkInAt, '2030-08-14 15:00:00');
      expect(lodging.parsedCheckIn.hour, 15);
      expect(lodging.booking!.name, 'Smith Wedding');
      expect(lodging.event!.title, 'Reception');
      expect(lodging.rooms.single.confirmationNumber, 'ABC123');
      expect(lodging.attachments.single.mimeType, 'image/jpeg');
    });

    test('tolerates missing optionals and malformed lists', () {
      final lodging = Lodging.fromJson({
        'id': 2,
        'name': 'Bare',
        'check_in_at': '2030-01-01 15:00:00',
        'check_out_at': '2030-01-02 11:00:00',
        'rooms': 'not-a-list',
      });
      expect(lodging.address, isNull);
      expect(lodging.booking, isNull);
      expect(lodging.rooms, isEmpty);
      expect(lodging.attachments, isEmpty);
    });
  });

  group('LodgingSummary.fromJson', () {
    test('parses counts and link ids', () {
      final s = LodgingSummary.fromJson({
        'id': 3,
        'name': 'Listed',
        'address': null,
        'check_in_at': '2030-02-01 15:00:00',
        'check_out_at': '2030-02-02 11:00:00',
        'room_count': 3,
        'attachment_count': 1,
        'booking_id': 7,
        'event_id': null,
      });
      expect(s.roomCount, 3);
      expect(s.bookingId, 7);
      expect(s.eventId, isNull);
    });
  });

  group('LodgingRoom.toJson', () {
    test('includes id only when set', () {
      expect(const LodgingRoom(label: 'King').toJson(), {'label': 'King'});
      expect(
        const LodgingRoom(id: 4, label: 'King', confirmationNumber: 'A1').toJson(),
        {'id': 4, 'label': 'King', 'confirmation_number': 'A1'},
      );
    });
  });
}
