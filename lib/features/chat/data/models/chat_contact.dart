class ChatContact {
  const ChatContact({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.context = '',
    this.isSub = false,
  });

  final int id;
  final String name;
  final String? avatarUrl;

  /// Human label for where you know them from, e.g. a band name.
  final String context;
  final bool isSub;

  factory ChatContact.fromJson(Map<String, dynamic> json) => ChatContact(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String? ?? '',
        avatarUrl: json['avatar_url'] as String?,
        context: json['context'] as String? ?? '',
        isSub: json['is_sub'] as bool? ?? false,
      );
}
