class ChatAttachment {
  const ChatAttachment({required this.id, required this.width, required this.height});
  final int id;
  final int width;
  final int height;

  factory ChatAttachment.fromJson(Map<String, dynamic> json) => ChatAttachment(
        id: (json['id'] as num).toInt(),
        width: (json['width'] as num?)?.toInt() ?? 0,
        height: (json['height'] as num?)?.toInt() ?? 0,
      );
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.userId,
    required this.userName,
    required this.body,
    required this.createdAt,
    this.userAvatarUrl,
    this.attachments = const [],
    this.editedAt,
    this.isDeleted = false,
  });

  final int id;
  final int conversationId;
  final int userId;
  final String userName;
  final String? userAvatarUrl;
  final String body;
  final List<ChatAttachment> attachments;
  final DateTime? editedAt;
  final bool isDeleted;
  final DateTime createdAt;

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: (json['id'] as num).toInt(),
        conversationId: (json['conversation_id'] as num).toInt(),
        userId: (json['user_id'] as num).toInt(),
        userName: json['user_name'] as String? ?? '',
        userAvatarUrl: json['user_avatar_url'] as String?,
        body: json['body'] as String? ?? '',
        attachments: (json['attachments'] as List? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(ChatAttachment.fromJson)
            .toList(),
        editedAt: json['edited_at'] != null
            ? DateTime.tryParse(json['edited_at'] as String)
            : null,
        isDeleted: json['is_deleted'] as bool? ?? false,
        // Stable fallback for an unparseable timestamp: epoch sorts a
        // malformed message as oldest instead of non-deterministically "new".
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );

  ChatMessage copyWith({
    int? id,
    String? body,
    List<ChatAttachment>? attachments,
    DateTime? editedAt,
    bool? isDeleted,
  }) =>
      ChatMessage(
        id: id ?? this.id,
        conversationId: conversationId,
        userId: userId,
        userName: userName,
        userAvatarUrl: userAvatarUrl,
        body: body ?? this.body,
        attachments: attachments ?? this.attachments,
        editedAt: editedAt ?? this.editedAt,
        isDeleted: isDeleted ?? this.isDeleted,
        createdAt: createdAt,
      );
}
