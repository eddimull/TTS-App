import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/core/network/geocoding.dart';

void main() {
  test('parseGeocodeResponse extracts the first result lat/lng', () {
    final point = parseGeocodeResponse({'results': [
      {'geometry': {'location': {'lat': 30.4, 'lng': -91.1}}}
    ]});
    expect(point, isNotNull);
    expect(point!.latitude, 30.4);
    expect(point.longitude, -91.1);
  });

  test('parseGeocodeResponse returns null for empty/missing results', () {
    expect(parseGeocodeResponse({'results': <dynamic>[]}), isNull);
    expect(parseGeocodeResponse({}), isNull);
    expect(parseGeocodeResponse({'results': null}), isNull);
  });

  test('GeoPoint equality', () {
    expect(const GeoPoint(1, 2), const GeoPoint(1, 2));
    expect(const GeoPoint(1, 2) == const GeoPoint(1, 3), false);
  });
}
