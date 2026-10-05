/// One row of the in-app feed, exactly as the backend presents it: the
/// server resolves `kind` and a mobile `deeplink`, so the client never
/// interprets stored payloads.
class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.kind,
    required this.text,
    required this.deeplink,
    required this.createdAt,
    this.readAt,
    this.seenAt,
  });

  final String id;
  final String kind;
  final String text;
  final String deeplink;
  final DateTime createdAt;
  final DateTime? readAt;
  final DateTime? seenAt;

  bool get isUnread => readAt == null;

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    DateTime? date(Object? v) => v == null ? null : DateTime.tryParse(v.toString());
    final deeplink = (json['deeplink'] ?? '').toString();
    return NotificationItem(
      id: (json['id'] ?? '').toString(),
      kind: (json['kind'] ?? 'dashboard').toString(),
      text: (json['text'] ?? 'New notification').toString(),
      deeplink: deeplink.startsWith('/') ? deeplink : '/dashboard',
      createdAt: date(json['created_at']) ?? DateTime.now(),
      readAt: date(json['read_at']),
      seenAt: date(json['seen_at']),
    );
  }

  NotificationItem copyWith({DateTime? readAt, DateTime? seenAt}) => NotificationItem(
        id: id,
        kind: kind,
        text: text,
        deeplink: deeplink,
        createdAt: createdAt,
        readAt: readAt ?? this.readAt,
        seenAt: seenAt ?? this.seenAt,
      );
}

class NotificationPage {
  const NotificationPage({required this.items, required this.nextCursor, required this.unseenCount});
  final List<NotificationItem> items;
  final String? nextCursor;
  final int unseenCount;
}
