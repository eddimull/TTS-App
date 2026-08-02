/// A substitute invited to one specific rehearsal.
class RehearsalSub {
  const RehearsalSub({
    required this.id,
    required this.name,
    this.email,
    this.phone,
    this.bandRoleId,
    this.roleName,
    this.userId,
  });

  final int id;
  final String name;
  final String? email;
  final String? phone;
  final int? bandRoleId;
  final String? roleName;
  final int? userId;

  /// Registered users get push + in-app visibility; ad-hoc invitees email only.
  bool get isRegistered => userId != null;

  factory RehearsalSub.fromJson(Map<String, dynamic> json) {
    return RehearsalSub(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String? ?? '',
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      bandRoleId: (json['band_role_id'] as num?)?.toInt(),
      roleName: json['role_name'] as String?,
      userId: (json['user_id'] as num?)?.toInt(),
    );
  }
}
