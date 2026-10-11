import 'package:dio/dio.dart';
import '../../../core/network/api_endpoints.dart';
import 'models/price_estimate.dart';
import 'models/pricing_settings.dart';

class PricingRepository {
  PricingRepository(this._dio);

  final Dio _dio;

  Future<PriceEstimate> estimate(int bandId, PriceEstimateRequest req) async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.mobileBandPriceEstimate(bandId),
      data: req.toJson(),
    );
    return PriceEstimate.fromJson(response.data ?? const {});
  }

  Future<PricingSettingsBundle> getSettings(int bandId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileBandPricingSettings(bandId),
    );
    return PricingSettingsBundle.fromJson(response.data ?? const {});
  }

  Future<PricingSettingsBundle> saveSettings(
      int bandId, PricingSettings settings) async {
    final response = await _dio.put<Map<String, dynamic>>(
      ApiEndpoints.mobileBandPricingSettings(bandId),
      data: {'settings': settings.toJson()},
    );
    return PricingSettingsBundle.fromJson(response.data ?? const {});
  }
}
