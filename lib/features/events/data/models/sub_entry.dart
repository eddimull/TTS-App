class SubEntry {
  const SubEntry({
    required this.id,
    required this.name,
    this.email,
    required this.bandRoleId,
    this.roleName,
    this.rosterMemberId,
    this.isCustom = false,
    this.priority = 0,
  });

  final int id;
  final String name;
  final String? email;
  final int bandRoleId;
  final String? roleName;
  final int? rosterMemberId;
  final bool isCustom;
  final int priority;

  factory SubEntry.fromJson(Map<String, dynamic> json) {
    return SubEntry(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String? ?? '',
      email: json['email'] as String?,
      bandRoleId: (json['band_role_id'] as num).toInt(),
      roleName: json['role_name'] as String?,
      rosterMemberId: json['roster_member_id'] == null
          ? null
          : (json['roster_member_id'] as num).toInt(),
      isCustom: json['is_custom'] as bool? ?? false,
      priority: (json['priority'] as num?)?.toInt() ?? 0,
    );
  }
}
