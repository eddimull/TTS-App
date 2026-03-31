class EventType {
  final int id;
  final String name;

  const EventType({required this.id, required this.name});

  factory EventType.fromJson(Map<String, dynamic> json) => EventType(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
      );
}
