/// A substitute associated with a band — either a confirmed sub (`status` =
/// 'active', backed by a `band_subs` link) or a pending band-level invitation
/// (`status` = 'pending', backed by `band_sub_invitations`).
///
/// Mirrors the unified payload from `BandSubsController@index`.
class BandSub {
  const BandSub({
    required this.id,
    required this.type,
    required this.status,
    required this.isRegistered,
    required this.name,
    this.userId,
    this.email,
    this.phone,
    this.bandRoleId,
    this.roleName,
  });

  final int id;

  /// 'band_sub' (active link) or 'invitation' (pending).
  final String type;

  /// 'active' or 'pending'.
  final String status;
  final bool isRegistered;
  final String name;
  final int? userId;
  final String? email;

  /// Only pending email-only invitations carry a phone; registered users
  /// (active subs) have none on file, so this is null for them.
  final String? phone;
  final int? bandRoleId;
  final String? roleName;

  bool get isPending => status == 'pending';

  /// Whether this row represents a pending invitation (revocable) vs an active
  /// band-sub link (removable). Drives which delete endpoint to call.
  bool get isInvitation => type == 'invitation';

  factory BandSub.fromJson(Map<String, dynamic> json) {
    return BandSub(
      id: (json['id'] as num).toInt(),
      type: json['type'] as String? ?? 'band_sub',
      status: json['status'] as String? ?? 'active',
      isRegistered: (json['is_registered'] as bool?) ?? false,
      name: json['name'] as String? ?? '',
      userId: (json['user_id'] as num?)?.toInt(),
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      bandRoleId: (json['band_role_id'] as num?)?.toInt(),
      roleName: json['role_name'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BandSub &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          type == other.type;

  @override
  int get hashCode => Object.hash(id, type);
}
