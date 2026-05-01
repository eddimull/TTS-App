class BandSummary {
  const BandSummary({
    required this.id,
    required this.name,
    required this.isOwner,
    this.isPersonal = false,
    this.logoUrl,
  });

  final int id;
  final String name;
  final bool isOwner;
  final bool isPersonal;
  final String? logoUrl;

  factory BandSummary.fromJson(Map<String, dynamic> json) {
    return BandSummary(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String,
      isOwner: (json['is_owner'] as bool?) ?? false,
      isPersonal: (json['is_personal'] as bool?) ?? false,
      logoUrl: json['logo_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'is_owner': isOwner,
        'is_personal': isPersonal,
        'logo_url': logoUrl,
      };

  @override
  String toString() =>
      'BandSummary(id: $id, name: $name, isOwner: $isOwner, isPersonal: $isPersonal)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BandSummary &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
