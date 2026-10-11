import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/core/network/api_endpoints.dart';
import 'package:tts_bandmate/features/pricing/data/models/price_estimate.dart';
import 'package:tts_bandmate/features/pricing/data/pricing_repository.dart';
import 'package:tts_bandmate/features/pricing/providers/pricing_provider.dart';

class _FakeDio extends Fake implements Dio {
  _FakeDio(this.responses);
  final Map<String, Object?> responses;
  final calls = <String>[];
  Object? lastBody;
  Object? error;

  Response<T> _resp<T>(String path) {
    if (error != null) throw error!;
    return Response<T>(
      data: responses[path] as T,
      statusCode: 200,
      requestOptions: RequestOptions(path: path),
    );
  }

  @override
  Future<Response<T>> get<T>(String path,
      {Object? data,
      Map<String, dynamic>? queryParameters,
      Options? options,
      CancelToken? cancelToken,
      ProgressCallback? onReceiveProgress}) async {
    calls.add('GET $path');
    return _resp<T>(path);
  }

  @override
  Future<Response<T>> post<T>(String path,
      {Object? data,
      Map<String, dynamic>? queryParameters,
      Options? options,
      CancelToken? cancelToken,
      ProgressCallback? onSendProgress,
      ProgressCallback? onReceiveProgress}) async {
    calls.add('POST $path');
    lastBody = data;
    return _resp<T>(path);
  }

  @override
  Future<Response<T>> put<T>(String path,
      {Object? data,
      Map<String, dynamic>? queryParameters,
      Options? options,
      CancelToken? cancelToken,
      ProgressCallback? onSendProgress,
      ProgressCallback? onReceiveProgress}) async {
    calls.add('PUT $path');
    lastBody = data;
    return _resp<T>(path);
  }
}

const _settingsBody = {
  'settings': {'standard_hours': 5, 'base_rates': {}},
  'event_types': [
    {'id': 1, 'name': 'Wedding'}
  ],
  'history': [],
};

void main() {
  const req = PriceEstimateRequest(eventTypeId: 1, date: '2027-05-15');

  test('estimate POSTs to the price-estimate endpoint', () async {
    final dio = _FakeDio({
      ApiEndpoints.mobileBandPriceEstimate(7): {
        'estimate': 5000,
        'confidence': 'medium',
      },
    });
    final e = await PricingRepository(dio).estimate(7, req);
    expect(dio.calls, ['POST /api/mobile/bands/7/price-estimate']);
    expect((dio.lastBody as Map)['event_type_id'], 1);
    expect(e.estimate, 5000.0);
    expect(e.confidence, 'medium');
  });

  test('getSettings / saveSettings use the settings endpoint', () async {
    final dio = _FakeDio(
        {ApiEndpoints.mobileBandPricingSettings(7): _settingsBody});
    final repo = PricingRepository(dio);
    final got = await repo.getSettings(7);
    expect(got.settings.standardHours, 5);
    final saved = await repo.saveSettings(7, got.settings.copyWith(roundTo: 25));
    expect(dio.calls, [
      'GET /api/mobile/bands/7/pricing-settings',
      'PUT /api/mobile/bands/7/pricing-settings',
    ]);
    expect(((dio.lastBody as Map)['settings'] as Map)['round_to'], 25.0);
    expect(saved.eventTypes.single.name, 'Wedding');
  });

  group('providers', () {
    ProviderContainer make(_FakeDio dio) {
      final c = ProviderContainer(overrides: [
        pricingRepositoryProvider.overrideWithValue(PricingRepository(dio)),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('priceEstimateProvider.run stores result', () async {
      final dio = _FakeDio({
        ApiEndpoints.mobileBandPriceEstimate(1): {'estimate': 1200.0},
      });
      final c = make(dio);
      final sub = c.listen(priceEstimateProvider, (_, __) {});
      expect(sub.read().value, isNull);
      await c.read(priceEstimateProvider.notifier).run(1, req);
      expect(sub.read().value!.estimate, 1200.0);
    });

    test('priceEstimateProvider.run surfaces 422 message', () async {
      final dio = _FakeDio({})
        ..error = DioException(
          requestOptions: RequestOptions(path: ''),
          response: Response(
            requestOptions: RequestOptions(path: ''),
            statusCode: 422,
            data: {
              'errors': {
                'date': ['The date field is required.']
              }
            },
          ),
        );
      final c = make(dio);
      final sub = c.listen(priceEstimateProvider, (_, __) {});
      await c.read(priceEstimateProvider.notifier).run(1, req);
      expect(sub.read().hasError, isTrue);
      expect(pricingErrorMessage(sub.read().error!),
          'The date field is required.');
    });

    test('pricingSettingsProvider loads and save replaces state', () async {
      final dio = _FakeDio(
          {ApiEndpoints.mobileBandPricingSettings(3): _settingsBody});
      final c = make(dio);
      final sub = c.listen(pricingSettingsProvider(3), (_, __) {});
      final bundle = await c.read(pricingSettingsProvider(3).future);
      expect(bundle.settings.standardHours, 5);
      await c
          .read(pricingSettingsProvider(3).notifier)
          .save(bundle.settings);
      expect(dio.calls.last, 'PUT /api/mobile/bands/3/pricing-settings');
      expect(sub.read().hasValue, isTrue);
    });
  });
}
