class BandInvitation {
  const BandInvitation({
    required this.id,
    required this.email,
    required this.inviteType,
    required this.key,
  });

  final int id;
  final String email;

  /// 'owner' or 'member'
  final String inviteType;
  final String key;

  factory BandInvitation.fromJson(Map<String, dynamic> json) {
    return BandInvitation(
      id: (json['id'] as num).toInt(),
      email: json['email'] as String,
      inviteType: json['invite_type'] as String,
      key: json['key'] as String,
    );
  }

  @override
  String toString() =>
      'BandInvitation(id: $id, email: $email, inviteType: $inviteType, key: $key)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BandInvitation &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
