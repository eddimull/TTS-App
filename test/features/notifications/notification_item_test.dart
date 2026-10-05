import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/notifications/data/models/notification_item.dart';

void main() {
  test('parses a presented row', () {
    final n = NotificationItem.fromJson({
      'id': 'a1b2',
      'kind': 'booking',
      'text': 'Payment received',
      'deeplink': '/bookings/1/42',
      'web_url': '/bands/1/booking/42',
      'read_at': null,
      'seen_at': '2026-10-05T10:00:00+00:00',
      'created_at': '2026-10-05T09:00:00+00:00',
    });
    expect(n.id, 'a1b2');
    expect(n.kind, 'booking');
    expect(n.deeplink, '/bookings/1/42');
    expect(n.isUnread, isTrue);
    expect(n.seenAt, isNotNull);
    expect(n.createdAt.toUtc().hour, 9);
  });

  test('tolerates missing fields with safe defaults', () {
    final n = NotificationItem.fromJson({'id': 'x', 'created_at': '2026-10-05T09:00:00+00:00'});
    expect(n.kind, 'dashboard');
    expect(n.text, 'New notification');
    expect(n.deeplink, '/dashboard');
    expect(n.readAt, isNull);
  });

  test('copyWith marks read', () {
    final n = NotificationItem.fromJson({'id': 'x', 'created_at': '2026-10-05T09:00:00+00:00'});
    expect(n.copyWith(readAt: DateTime(2026, 10, 5)).isUnread, isFalse);
  });
}
