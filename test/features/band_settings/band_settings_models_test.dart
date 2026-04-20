import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/band_settings/data/models/band_detail.dart';
import 'package:tts_bandmate/features/band_settings/data/models/band_member.dart';
import 'package:tts_bandmate/features/band_settings/data/models/band_invitation.dart';

void main() {
  group('BandDetail.fromJson', () {
    test('test_parses_all_fields', () {
      final detail = BandDetail.fromJson({
        'id': 42,
        'name': 'The Rocking Eds',
        'site_name': 'the-rocking-eds',
        'address': '123 Main St',
        'city': 'Nashville',
        'state': 'TN',
        'zip': '37201',
        'logo_url': 'https://example.com/logo.png',
      });
      expect(detail.id, 42);
      expect(detail.name, 'The Rocking Eds');
      expect(detail.siteName, 'the-rocking-eds');
      expect(detail.address, '123 Main St');
      expect(detail.city, 'Nashville');
      expect(detail.state, 'TN');
      expect(detail.zip, '37201');
      expect(detail.logoUrl, 'https://example.com/logo.png');
    });

    test('test_handles_null_optional_fields', () {
      final detail = BandDetail.fromJson({
        'id': 1,
        'name': 'Band',
        'site_name': 'band',
      });
      expect(detail.address, '');
      expect(detail.city, '');
      expect(detail.state, '');
      expect(detail.zip, '');
      expect(detail.logoUrl, isNull);
    });
  });

  group('BandMember.fromJson', () {
    test('test_parses_member_with_permissions', () {
      final member = BandMember.fromJson({
        'id': 5,
        'name': 'Jane Doe',
        'is_owner': false,
        'permissions': {
          'read:events': true,
          'write:events': false,
          'read:bookings': true,
          'write:bookings': false,
          'read:rehearsals': true,
          'write:rehearsals': false,
          'read:charts': true,
          'write:charts': false,
          'read:songs': true,
          'write:songs': false,
          'read:media': false,
          'write:media': false,
          'read:invoices': false,
          'write:invoices': false,
          'read:proposals': false,
          'write:proposals': false,
          'read:colors': false,
          'write:colors': false,
        },
      });
      expect(member.id, 5);
      expect(member.name, 'Jane Doe');
      expect(member.isOwner, false);
      expect(member.permissions['read:events'], true);
      expect(member.permissions['write:events'], false);
    });

    test('test_parses_owner', () {
      final member = BandMember.fromJson({
        'id': 1,
        'name': 'Eddie',
        'is_owner': true,
        'permissions': {},
      });
      expect(member.isOwner, true);
    });
  });

  group('BandInvitation.fromJson', () {
    test('test_parses_invitation', () {
      final inv = BandInvitation.fromJson({
        'id': 99,
        'email': 'new@example.com',
        'invite_type': 'member',
        'key': 'abc-123',
      });
      expect(inv.id, 99);
      expect(inv.email, 'new@example.com');
      expect(inv.inviteType, 'member');
      expect(inv.key, 'abc-123');
    });
  });
}
