/// Editable account profile returned by GET /api/mobile/account.
///
/// Mirrors the fields the web Account page exposes. Password is never returned
/// by the API; it is write-only via the update endpoint.
class AccountProfile {
  const AccountProfile({
    required this.id,
    required this.name,
    required this.email,
    this.address1,
    this.address2,
    this.city,
    this.stateId,
    this.countryId,
    this.zip,
    required this.emailNotifications,
  });

  final int id;
  final String name;
  final String email;
  final String? address1;
  final String? address2;
  final String? city;
  final String? stateId;
  final String? countryId;
  final String? zip;
  final bool emailNotifications;

  factory AccountProfile.fromJson(Map<String, dynamic> json) {
    return AccountProfile(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      address1: json['address1'] as String?,
      address2: json['address2'] as String?,
      city: json['city'] as String?,
      // state_id / country_id are stored as strings server-side, but tolerate
      // numeric JSON just in case.
      stateId: json['state_id']?.toString(),
      countryId: json['country_id']?.toString(),
      zip: json['zip'] as String?,
      emailNotifications: json['email_notifications'] as bool? ?? true,
    );
  }
}

/// A selectable state/province in the country/state pickers.
class StateOption {
  const StateOption({
    required this.id,
    required this.name,
    required this.countryId,
  });

  final String id;
  final String name;
  final String countryId;

  factory StateOption.fromJson(Map<String, dynamic> json) {
    return StateOption(
      id: json['state_id'].toString(),
      name: json['state_name'] as String? ?? '',
      countryId: json['country_id'].toString(),
    );
  }
}

/// A selectable country in the country picker.
class CountryOption {
  const CountryOption({required this.id, required this.name});

  final String id;
  final String name;

  factory CountryOption.fromJson(Map<String, dynamic> json) {
    return CountryOption(
      id: json['id'].toString(),
      name: json['country_name'] as String? ?? '',
    );
  }
}
