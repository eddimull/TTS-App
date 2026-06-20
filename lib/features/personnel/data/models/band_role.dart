class BandRole {
  const BandRole({
    required this.id,
    required this.name,
    required this.displayOrder,
    required this.isActive,
    required this.rosterMembersCount,
    required this.eventMembersCount,
    required this.substituteCallListsCount,
  });

  final int id;
  final String name;
  final int displayOrder;
  final bool isActive;
  final int rosterMembersCount;
  final int eventMembersCount;
  final int substituteCallListsCount;

  factory BandRole.fromJson(Map<String, dynamic> json) {
    return BandRole(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String,
      displayOrder: (json['display_order'] as num?)?.toInt() ?? 0,
      isActive: (json['is_active'] as bool?) ?? true,
      rosterMembersCount: (json['roster_members_count'] as num?)?.toInt() ?? 0,
      eventMembersCount: (json['event_members_count'] as num?)?.toInt() ?? 0,
      substituteCallListsCount:
          (json['substitute_call_lists_count'] as num?)?.toInt() ?? 0,
    );
  }

  BandRole copyWith({
    String? name,
    int? displayOrder,
    bool? isActive,
  }) {
    return BandRole(
      id: id,
      name: name ?? this.name,
      displayOrder: displayOrder ?? this.displayOrder,
      isActive: isActive ?? this.isActive,
      rosterMembersCount: rosterMembersCount,
      eventMembersCount: eventMembersCount,
      substituteCallListsCount: substituteCallListsCount,
    );
  }

  @override
  String toString() =>
      'BandRole(id: $id, name: $name, displayOrder: $displayOrder, isActive: $isActive)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BandRole && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
