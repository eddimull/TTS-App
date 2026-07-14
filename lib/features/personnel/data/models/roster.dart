class RosterMember {
  const RosterMember({
    required this.id,
    required this.name,
    this.userId,
    this.slotId,
    this.email,
    this.phone,
    this.role,
    this.bandRoleId,
    this.notes,
    required this.isActive,
    required this.isUser,
  });

  final int id;
  final String name;
  final int? userId;
  final int? slotId;
  final String? email;
  final String? phone;
  /// Denormalised display label for the member's instrument/position
  /// (e.g. "Trumpet", "Bass"). Distinct from [bandRoleId], which is the FK
  /// to a typed BandRole record. Use [role] for display; use [bandRoleId]
  /// for filtering/grouping against the roles list.
  final String? role;
  final int? bandRoleId;
  final String? notes;
  final bool isActive;
  final bool isUser;

  factory RosterMember.fromJson(Map<String, dynamic> json) {
    // Raw Eloquent payloads (e.g. the rosters index) leave the `name` column
    // null for user-linked members; the display label is the appended
    // `display_name`, with the source of truth on the nested user.
    final user = json['user'] as Map<String, dynamic>?;
    final name = json['display_name'] as String? ??
        json['name'] as String? ??
        user?['name'] as String? ??
        '';
    return RosterMember(
      id: (json['id'] as num).toInt(),
      name: name,
      userId: (json['user_id'] as num?)?.toInt(),
      slotId: (json['slot_id'] as num?)?.toInt(),
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      role: json['role'] as String?,
      bandRoleId: (json['band_role_id'] as num?)?.toInt(),
      notes: json['notes'] as String?,
      isActive: (json['is_active'] as bool?) ?? true,
      isUser: (json['is_user'] as bool?) ?? false,
    );
  }

  RosterMember copyWith({
    String? name,
    String? email,
    String? phone,
    String? role,
    int? bandRoleId,
    int? slotId,
    String? notes,
    bool? isActive,
  }) {
    return RosterMember(
      id: id,
      name: name ?? this.name,
      userId: userId,
      slotId: slotId ?? this.slotId,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      bandRoleId: bandRoleId ?? this.bandRoleId,
      notes: notes ?? this.notes,
      isActive: isActive ?? this.isActive,
      isUser: isUser,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RosterMember && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'RosterMember(id: $id, name: $name, isActive: $isActive)';
}

class RosterSlot {
  const RosterSlot({
    required this.id,
    required this.name,
    this.bandRoleId,
    this.bandRoleName,
    required this.isRequired,
    required this.quantity,
    this.notes,
    required this.memberCount,
  });

  final int id;
  final String name;
  final int? bandRoleId;
  final String? bandRoleName;
  final bool isRequired;
  final int quantity;
  final String? notes;
  final int memberCount;

  factory RosterSlot.fromJson(Map<String, dynamic> json) {
    return RosterSlot(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String? ?? '',
      bandRoleId: (json['band_role_id'] as num?)?.toInt(),
      bandRoleName: json['band_role_name'] as String?,
      isRequired: (json['is_required'] as bool?) ?? false,
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      notes: json['notes'] as String?,
      memberCount: (json['member_count'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RosterSlot && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'RosterSlot(id: $id, name: $name)';
}

class Roster {
  const Roster({
    required this.id,
    required this.name,
    this.description,
    required this.isDefault,
    required this.isActive,
    required this.membersCount,
    this.members = const [],
    this.slots = const [],
  });

  final int id;
  final String name;
  final String? description;
  final bool isDefault;
  final bool isActive;
  final int membersCount;
  final List<RosterMember> members;
  final List<RosterSlot> slots;

  factory Roster.fromJson(Map<String, dynamic> json) {
    final rawMembers = json['members'] as List<dynamic>? ?? [];
    final rawSlots = json['slots'] as List<dynamic>? ?? [];
    return Roster(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      isDefault: (json['is_default'] as bool?) ?? false,
      isActive: (json['is_active'] as bool?) ?? true,
      membersCount: (json['members_count'] as num?)?.toInt() ?? rawMembers.length,
      members: rawMembers
          .map((m) => RosterMember.fromJson(m as Map<String, dynamic>))
          .toList(),
      slots: rawSlots
          .map((s) => RosterSlot.fromJson(s as Map<String, dynamic>))
          .toList(),
    );
  }

  Roster copyWith({
    String? name,
    String? description,
    bool? isDefault,
    bool? isActive,
    int? membersCount,
    List<RosterMember>? members,
    List<RosterSlot>? slots,
  }) {
    return Roster(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      isDefault: isDefault ?? this.isDefault,
      isActive: isActive ?? this.isActive,
      membersCount: membersCount ?? this.membersCount,
      members: members ?? this.members,
      slots: slots ?? this.slots,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Roster && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Roster(id: $id, name: $name, isDefault: $isDefault)';
}

/// A single person surfaced by the future-events reconcile diff.
class RosterEventDiffEntry {
  const RosterEventDiffEntry({
    required this.rosterMemberId,
    required this.displayName,
    required this.eventCount,
  });

  /// Null for legacy event members not linked to a roster member; such rows
  /// can be surfaced but not selected (the backend reconcile keys on this id).
  final int? rosterMemberId;
  final String displayName;
  final int eventCount;

  factory RosterEventDiffEntry.fromJson(Map<String, dynamic> json) {
    return RosterEventDiffEntry(
      rosterMemberId: (json['roster_member_id'] as num?)?.toInt(),
      displayName: json['display_name'] as String? ?? 'Unknown',
      eventCount: (json['event_count'] as num?)?.toInt() ?? 0,
    );
  }
}

/// The difference between a roster's current membership and the members on its
/// future events.
class RosterEventDiff {
  const RosterEventDiff({
    this.extra = const [],
    this.missing = const [],
  });

  /// People on future events who are no longer active roster members (removable).
  final List<RosterEventDiffEntry> extra;

  /// Active roster members absent from one or more future events (addable).
  final List<RosterEventDiffEntry> missing;

  bool get isEmpty => extra.isEmpty && missing.isEmpty;

  factory RosterEventDiff.fromJson(Map<String, dynamic> json) {
    List<RosterEventDiffEntry> parse(String key) =>
        ((json[key] as List<dynamic>?) ?? [])
            .map((e) =>
                RosterEventDiffEntry.fromJson(e as Map<String, dynamic>))
            .toList();
    return RosterEventDiff(
      extra: parse('extra'),
      missing: parse('missing'),
    );
  }
}
