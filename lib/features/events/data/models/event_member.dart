class EventMember {
  const EventMember({
    this.id, // null for synthetic unfilled slots (no EventMember row yet)
    this.userId,
    required this.name,
    this.attendanceStatus,
    this.role,
    this.slotName,
    this.sectionName,
    this.bandRoleId,
    this.slotId,
    this.rosterMemberId,
    this.isFilled = true,
    this.isSub = false,
  });

  final int? id; // null for synthetic unfilled slots
  final int? userId;
  final String name;

  /// One of "confirmed", "pending", "absent", or null.
  final String? attendanceStatus;

  /// Legacy: band role name (section). Prefer [sectionName].
  final String? role;

  /// Instrument/position name within the section, e.g. "Bass", "Trumpet".
  final String? slotName;

  /// Section name, e.g. "RHYTHM", "HORNS". Same as [role].
  final String? sectionName;

  final int? bandRoleId;
  final int? slotId;
  final int? rosterMemberId;
  final bool isFilled;
  final bool isSub;

  /// The section to group by (prefers explicit sectionName, falls back to role).
  String get groupKey => sectionName ?? role ?? 'Other';

  factory EventMember.fromJson(Map<String, dynamic> json) {
    return EventMember(
      id: json['id'] == null ? null : (json['id'] as num).toInt(),
      userId: json['user_id'] == null
          ? null
          : (json['user_id'] as num).toInt(),
      name: json['name'] as String? ?? '',
      attendanceStatus: json['attendance_status'] as String?,
      role: json['role'] as String?,
      slotName: json['slot_name'] as String?,
      sectionName: json['section_name'] as String?,
      bandRoleId: json['band_role_id'] == null
          ? null
          : (json['band_role_id'] as num).toInt(),
      slotId: json['slot_id'] == null
          ? null
          : (json['slot_id'] as num).toInt(),
      rosterMemberId: json['roster_member_id'] == null
          ? null
          : (json['roster_member_id'] as num).toInt(),
      isFilled: json['is_filled'] as bool? ??
          (json['user_id'] != null || json['name'] != null),
      isSub: json['is_sub'] as bool? ?? false,
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
          id == other.id &&
          slotId == other.slotId;

  @override
  int get hashCode => Object.hash(id, slotId);
}
