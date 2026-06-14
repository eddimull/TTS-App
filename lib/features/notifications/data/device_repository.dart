import 'package:dio/dio.dart';

import '../../../core/network/api_endpoints.dart';

/// Registers/deregisters this device's push token with the backend.
class DeviceRepository {
  DeviceRepository(this._dio);
  final Dio _dio;

  Future<void> register({required String token, required String platform}) {
    return _dio.post<void>(
      ApiEndpoints.mobileDevices,
      data: {'token': token, 'platform': platform},
    );
  }

  Future<void> deregister(String token) {
    return _dio.delete<void>(ApiEndpoints.mobileDevice(token));
  }
}
