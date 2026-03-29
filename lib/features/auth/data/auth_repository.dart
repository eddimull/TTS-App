import 'package:dio/dio.dart';
import '../../../core/network/api_endpoints.dart';
import 'models/auth_user.dart';
import 'models/band_summary.dart';

class AuthRepository {
  AuthRepository(this._dio);

  final Dio _dio;

  /// Authenticate with email/password and retrieve a Sanctum token.
  ///
  /// Returns a record containing the raw token, the authenticated user, and
  /// the list of bands the user belongs to.
  Future<({String token, AuthUser user, List<BandSummary> bands})> login(
    String email,
    String password,
    String deviceName,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.mobileToken,
      data: {
        'email': email,
        'password': password,
        'device_name': deviceName,
      },
    );

    final data = response.data!;
    final token = data['token'] as String;
    final user = AuthUser.fromJson(data['user'] as Map<String, dynamic>);
    final bandList = (data['bands'] as List<dynamic>)
        .map((b) => BandSummary.fromJson(b as Map<String, dynamic>))
        .toList();

    return (token: token, user: user, bands: bandList);
  }

  /// Fetch the current authenticated user and their bands.
  ///
  /// Requires a valid Bearer token already attached by the [ApiClient] interceptor.
  Future<({AuthUser user, List<BandSummary> bands})> getMe() async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileMe,
    );

    final data = response.data!;
    final user = AuthUser.fromJson(data['user'] as Map<String, dynamic>);
    final bandList = (data['bands'] as List<dynamic>)
        .map((b) => BandSummary.fromJson(b as Map<String, dynamic>))
        .toList();

    return (user: user, bands: bandList);
  }

  /// Revoke the current device token on the server.
  Future<void> logout() async {
    await _dio.delete<void>(ApiEndpoints.mobileLogout);
  }
}
