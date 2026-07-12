class ChatParticipant {
  const ChatParticipant({
    required this.userId,
    required this.name,
    this.avatarUrl,
    this.lastReadAt,
  });

  final int userId;
  final String name;
  final String? avatarUrl;
  final DateTime? lastReadAt;

  factory ChatParticipant.fromJson(Map<String, dynamic> json) => ChatParticipant(
        userId: (json['user_id'] as num).toInt(),
        name: json['name'] as String? ?? '',
        avatarUrl: json['avatar_url'] as String?,
        lastReadAt: json['last_read_at'] != null
            ? DateTime.tryParse(json['last_read_at'] as String)
            : null,
      );

  ChatParticipant copyWith({DateTime? lastReadAt}) => ChatParticipant(
        userId: userId,
        name: name,
        avatarUrl: avatarUrl,
        lastReadAt: lastReadAt ?? this.lastReadAt,
      );
}
