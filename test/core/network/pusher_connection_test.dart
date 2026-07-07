import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/core/network/pusher_connection.dart';

void main() {
  group('decodePusherData', () {
    test('decodes a JSON object string', () {
      expect(
        decodePusherData('{"model":"bookings","id":1,"action":"updated"}'),
        {'model': 'bookings', 'id': 1, 'action': 'updated'},
      );
    });

    test('passes through an already-decoded map', () {
      expect(decodePusherData({'a': 1}), {'a': 1});
    });

    test('returns null for null, empty, non-JSON, and non-object payloads', () {
      expect(decodePusherData(null), isNull);
      expect(decodePusherData(''), isNull);
      expect(decodePusherData('not json'), isNull);
      expect(decodePusherData('[1,2]'), isNull);
      expect(decodePusherData(42), isNull);
    });
  });
}
