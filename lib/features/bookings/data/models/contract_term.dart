class ContractTerm {
  const ContractTerm({
    required this.id,
    required this.title,
    required this.content,
  });

  /// Client-side stable id used for reorder/keying.
  /// Not persisted to the server.
  final int id;
  final String title;
  final String content;

  factory ContractTerm.fromJson(Map<String, dynamic> json) => ContractTerm(
        id: -1,
        title: (json['title'] as String?) ?? '',
        content: (json['content'] as String?) ?? '',
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        'content': content,
      };

  ContractTerm copyWith({String? title, String? content}) => ContractTerm(
        id: id,
        title: title ?? this.title,
        content: content ?? this.content,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ContractTerm &&
          id == other.id &&
          title == other.title &&
          content == other.content;

  @override
  int get hashCode => Object.hash(id, title, content);
}
