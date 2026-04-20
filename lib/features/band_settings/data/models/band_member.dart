class BandMember {
  const BandMember({
    required this.id,
    required this.name,
    required this.isOwner,
    required this.permissions,
  });

  final int id;
  final String name;
  final bool isOwner;

  /// Keys are Spatie permission strings e.g. 'read:events', 'write:events'.
  final Map<String, bool> permissions;

  factory BandMember.fromJson(Map<String, dynamic> json) {
    final rawPerms = json['permissions'] as Map<dynamic, dynamic>? ?? {};
    return BandMember(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String,
      isOwner: (json['is_owner'] as bool?) ?? false,
      permissions: rawPerms.map((k, v) => MapEntry(k as String, v as bool)),
    );
  }

  BandMember withPermission(String permission, {required bool granted}) {
    return BandMember(
      id: id,
      name: name,
      isOwner: isOwner,
      permissions: {...permissions, permission: granted},
    );
  }

  @override
  String toString() =>
      'BandMember(id: $id, name: $name, isOwner: $isOwner, permissions: $permissions)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BandMember &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
