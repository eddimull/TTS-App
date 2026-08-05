import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/shared/utils/maps_launch.dart';

void main() {
  group('mapsSearchUri', () {
    test('prefers coordinates over address and name', () {
      final uri = mapsSearchUri(
          lat: 30.4, lng: -91.1, address: '123 Main St', name: 'Hotel');
      expect(uri.toString(), 'https://maps.google.com/?q=30.4,-91.1');
    });

    test('falls back to encoded address', () {
      final uri = mapsSearchUri(address: '123 Main St', name: 'Hotel');
      expect(uri.toString(), 'https://maps.google.com/?q=123%20Main%20St');
    });

    test('falls back to encoded name', () {
      final uri = mapsSearchUri(name: 'Hampton Inn');
      expect(uri.toString(), 'https://maps.google.com/?q=Hampton%20Inn');
    });

    test('returns null when nothing is provided', () {
      expect(mapsSearchUri(), isNull);
      expect(mapsSearchUri(address: '', name: ''), isNull);
    });
  });
}
