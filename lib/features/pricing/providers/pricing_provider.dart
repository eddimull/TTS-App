import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/core_providers.dart';
import '../data/models/price_estimate.dart';
import '../data/models/pricing_settings.dart';
import '../data/pricing_repository.dart';

final pricingRepositoryProvider = Provider<PricingRepository>((ref) {
  return PricingRepository(ref.watch(apiClientProvider).dio);
});

/// Turns a Dio/other error into a short user-facing message.
String pricingErrorMessage(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map) {
      final errors = data['errors'];
      if (errors is Map && errors.isNotEmpty) {
        final first = errors.values.first;
        if (first is List && first.isNotEmpty) return first.first.toString();
        return first.toString();
      }
      final msg = data['message'];
      if (msg is String && msg.isNotEmpty) return msg;
    }
    if (error.response?.statusCode == 403) {
      return 'Only band owners can use the price estimator.';
    }
  }
  return 'Could not get an estimate. Please try again.';
}

/// Holds the latest estimate (null = nothing requested yet). Auto-disposed so
/// the standalone screen and the booking-form sheet never share a result.
class PriceEstimateNotifier extends AsyncNotifier<PriceEstimate?> {
  @override
  Future<PriceEstimate?> build() async => null;

  Future<void> run(int bandId, PriceEstimateRequest request) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(pricingRepositoryProvider).estimate(bandId, request),
    );
  }
}

final priceEstimateProvider =
    AsyncNotifierProvider.autoDispose<PriceEstimateNotifier, PriceEstimate?>(
  PriceEstimateNotifier.new,
);

/// Pricing rules for a band. [save] PUTs and replaces state with the response.
class PricingSettingsNotifier extends AsyncNotifier<PricingSettingsBundle> {
  PricingSettingsNotifier(this.arg);

  final int arg;

  @override
  Future<PricingSettingsBundle> build() =>
      ref.watch(pricingRepositoryProvider).getSettings(arg);

  /// Throws on failure so the caller can show an error; state is left intact.
  Future<void> save(PricingSettings settings) async {
    final saved = await ref
        .read(pricingRepositoryProvider)
        .saveSettings(arg, settings);
    state = AsyncValue.data(saved);
  }
}

final pricingSettingsProvider = AsyncNotifierProvider.autoDispose
    .family<PricingSettingsNotifier, PricingSettingsBundle, int>(
  PricingSettingsNotifier.new,
);
