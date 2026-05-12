import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';

void main() {
  test('BandSummary parses address fields', () {
    final b = BandSummary.fromJson({
      'id': 1,
      'name': 'Band',
      'is_owner': true,
      'logo': 'https://x/logo.png',
      'address': '123 Music Row',
      'city': 'Nashville',
      'state': 'TN',
      'zip': '37203',
    });
    expect(b.address, '123 Music Row');
    expect(b.city, 'Nashville');
    expect(b.state, 'TN');
    expect(b.zip, '37203');
    expect(b.logo, 'https://x/logo.png');
  });

  test('BandSummary still works without address fields (back-compat)', () {
    final b = BandSummary.fromJson({
      'id': 1,
      'name': 'Band',
      'is_owner': true,
    });
    expect(b.address, isNull);
    expect(b.city, isNull);
    expect(b.state, isNull);
    expect(b.zip, isNull);
    expect(b.logo, isNull);
  });
}
