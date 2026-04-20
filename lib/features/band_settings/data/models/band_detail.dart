class BandDetail {
  const BandDetail({
    required this.id,
    required this.name,
    required this.siteName,
    required this.address,
    required this.city,
    required this.state,
    required this.zip,
    this.logoUrl,
  });

  final int id;
  final String name;
  final String siteName;
  final String address;
  final String city;
  final String state;
  final String zip;
  final String? logoUrl;

  factory BandDetail.fromJson(Map<String, dynamic> json) {
    return BandDetail(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String,
      siteName: json['site_name'] as String,
      address: json['address'] as String? ?? '',
      city: json['city'] as String? ?? '',
      state: json['state'] as String? ?? '',
      zip: json['zip'] as String? ?? '',
      logoUrl: json['logo_url'] as String?,
    );
  }

  BandDetail copyWith({
    String? name,
    String? siteName,
    String? address,
    String? city,
    String? state,
    String? zip,
    String? logoUrl,
  }) {
    return BandDetail(
      id: id,
      name: name ?? this.name,
      siteName: siteName ?? this.siteName,
      address: address ?? this.address,
      city: city ?? this.city,
      state: state ?? this.state,
      zip: zip ?? this.zip,
      logoUrl: logoUrl ?? this.logoUrl,
    );
  }
}
