class BandSummary {
  const BandSummary({
    required this.id,
    required this.name,
    required this.isOwner,
    this.isPersonal = false,
    this.logoUrl,
    this.logo,
    this.address,
    this.city,
    this.state,
    this.zip,
  });

  final int id;
  final String name;
  final bool isOwner;
  final bool isPersonal;

  /// Legacy field; new code should read [logo].
  final String? logoUrl;

  /// Band logo URL as returned by web/mobile APIs.
  final String? logo;
  final String? address;
  final String? city;
  final String? state;
  final String? zip;

  factory BandSummary.fromJson(Map<String, dynamic> json) {
    return BandSummary(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String,
      isOwner: (json['is_owner'] as bool?) ?? false,
      isPersonal: (json['is_personal'] as bool?) ?? false,
      logoUrl: json['logo_url'] as String?,
      logo: (json['logo'] as String?) ?? (json['logo_url'] as String?),
      address: json['address'] as String?,
      city: json['city'] as String?,
      state: json['state'] as String?,
      zip: json['zip'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'is_owner': isOwner,
        'is_personal': isPersonal,
        'logo_url': logoUrl,
        'logo': logo,
        'address': address,
        'city': city,
        'state': state,
        'zip': zip,
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
