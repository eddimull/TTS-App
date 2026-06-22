import 'package:dio/dio.dart';
import '../../../core/network/api_endpoints.dart';
import 'models/account_profile.dart';

class AccountRepository {
  AccountRepository(this._dio);

  final Dio _dio;

  /// Fetch the editable profile plus the state/country lookup lists.
  Future<({AccountProfile profile, List<StateOption> states, List<CountryOption> countries})>
      getAccount() async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileAccount,
    );
    final data = response.data!;

    final profile =
        AccountProfile.fromJson(data['account'] as Map<String, dynamic>);
    final states = (data['states'] as List<dynamic>? ?? [])
        .map((s) => StateOption.fromJson(s as Map<String, dynamic>))
        .toList();
    final countries = (data['countries'] as List<dynamic>? ?? [])
        .map((c) => CountryOption.fromJson(c as Map<String, dynamic>))
        .toList();

    return (profile: profile, states: states, countries: countries);
  }

  /// Update the profile. [password] is only sent when non-null/non-empty so the
  /// existing password is preserved otherwise (matches the web behaviour).
  Future<AccountProfile> updateAccount({
    required String name,
    required String email,
    String? password,
    String? address1,
    String? address2,
    String? city,
    String? stateId,
    String? countryId,
    String? zip,
    required bool emailNotifications,
    String? movedAt,
  }) async {
    final data = <String, dynamic>{
      'name': name,
      'email': email,
      'address1': address1,
      'address2': address2,
      'city': city,
      'state_id': stateId,
      'country_id': countryId,
      'zip': zip,
      'email_notifications': emailNotifications,
    };

    if (password != null && password.isNotEmpty) {
      data['password'] = password;
      data['password_confirmation'] = password;
    }

    // Only sent when the user changed their address: tells the backend which
    // events to recompute mileage for (those on/after the move date). Omitted
    // otherwise, in which case the backend leaves cached mileage untouched.
    if (movedAt != null) {
      data['moved_at'] = movedAt;
    }

    final response = await _dio.patch<Map<String, dynamic>>(
      ApiEndpoints.mobileAccount,
      data: data,
    );
    return AccountProfile.fromJson(
        response.data!['account'] as Map<String, dynamic>);
  }

  /// Request account deletion. The server emails a signed confirmation link;
  /// the account is only removed once that link is opened. Returns nothing —
  /// success means "confirmation email sent".
  Future<void> requestDeletion() async {
    await _dio.delete<void>(ApiEndpoints.mobileAccount);
  }
}
