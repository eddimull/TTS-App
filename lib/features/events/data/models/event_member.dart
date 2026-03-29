class EventMember {
  const EventMember({
    required this.id,
    this.userId,
    required this.name,
    this.attendanceStatus,
    this.role,
  });

  final int id;
  final int? userId;
  final String name;

  /// One of "confirmed", "pending", "absent", or null.
  final String? attendanceStatus;

  final String? role;

  factory EventMember.fromJson(Map<String, dynamic> json) {
    return EventMember(
      id: (json['id'] as num).toInt(),
      userId: json['user_id'] == null
          ? null
          : (json['user_id'] as num).toInt(),
      name: json['name'] as String,
      attendanceStatus: json['attendance_status'] as String?,
      role: json['role'] as String?,
    );
  }

  @override
  String toString() =>
      'EventMember(id: $id, name: $name, attendanceStatus: $attendanceStatus)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EventMember &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
