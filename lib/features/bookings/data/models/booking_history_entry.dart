class BookingHistoryChange {
  final String field;
  final String? oldValue;
  final String? newValue;

  const BookingHistoryChange({
    required this.field,
    this.oldValue,
    this.newValue,
  });

  factory BookingHistoryChange.fromJson(Map<String, dynamic> json) =>
      BookingHistoryChange(
        field: json['field'] as String? ?? '',
        oldValue: json['old']?.toString(),
        newValue: json['new']?.toString(),
      );
}

class BookingHistoryEntry {
  final int id;
  final String description;
  final String? eventType;
  final String? category;
  final String? causerName;
  final List<BookingHistoryChange> changes;
  final String? createdAt;
  final String? createdAtHuman;

  const BookingHistoryEntry({
    required this.id,
    required this.description,
    this.eventType,
    this.category,
    this.causerName,
    this.changes = const [],
    this.createdAt,
    this.createdAtHuman,
  });

  factory BookingHistoryEntry.fromJson(Map<String, dynamic> json) {
    final changesRaw = json['changes'] as List<dynamic>? ?? [];
    return BookingHistoryEntry(
      id: json['id'] as int? ?? 0,
      description: json['description'] as String? ?? '',
      eventType: json['event_type'] as String?,
      category: json['category'] as String?,
      causerName:
          (json['causer'] as Map<String, dynamic>?)?['name'] as String?,
      changes: changesRaw
          .map((c) =>
              BookingHistoryChange.fromJson(c as Map<String, dynamic>))
          .toList(),
      createdAt: json['created_at'] as String?,
      createdAtHuman: json['created_at_human'] as String?,
    );
  }
}
