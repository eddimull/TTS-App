class Conversation {
  const Conversation({
    required this.id,
    required this.type,
    required this.title,
    this.bandId,
    this.lastMessagePreview,
    this.lastMessageAt,
    this.unreadCount = 0,
    this.canModerate = false,
  });

  final int id;
  final String type; // 'dm' | 'band' | 'topic'
  final String title;
  final int? bandId;
  final String? lastMessagePreview;
  final DateTime? lastMessageAt;
  final int unreadCount;
  final bool canModerate;

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
        id: (json['id'] as num).toInt(),
        type: json['type'] as String? ?? 'topic',
        title: json['title'] as String? ?? '',
        bandId: (json['band_id'] as num?)?.toInt(),
        lastMessagePreview: json['last_message_preview'] as String?,
        lastMessageAt: json['last_message_at'] != null
            ? DateTime.tryParse(json['last_message_at'] as String)
            : null,
        unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
        canModerate: json['can_moderate'] as bool? ?? false,
      );
}
