import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tts_bandmate/core/providers/core_providers.dart';
import 'models/chart.dart';

class LibraryRepository {
  LibraryRepository(this._dio);

  final Dio _dio;

  /// Fetches the list of charts for [bandId].
  Future<List<Chart>> getCharts(int bandId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileBandCharts(bandId),
    );

    final data = response.data!;
    final rawList = data['charts'] as List<dynamic>;
    return rawList
        .cast<Map<String, dynamic>>()
        .map(Chart.fromJson)
        .toList();
  }

  /// Fetches the full detail for a single chart identified by [chartId].
  Future<Chart> getChart(int bandId, int chartId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileBandChart(bandId, chartId),
    );

    final data = response.data!;
    return Chart.fromJson(data['chart'] as Map<String, dynamic>);
  }
}

final libraryRepositoryProvider = Provider<LibraryRepository>((ref) {
  return LibraryRepository(ref.watch(apiClientProvider).dio);
});
