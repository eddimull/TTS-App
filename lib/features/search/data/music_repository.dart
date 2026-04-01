import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tts_bandmate/core/providers/core_providers.dart';
import 'models/search_models.dart';

class MusicRepository {
  MusicRepository(this._dio);

  final Dio _dio;

  Future<List<SongResult>> songs(int bandId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileBandSongs(bandId),
    );
    final list = response.data!['songs'] as List<dynamic>? ?? [];
    return list
        .cast<Map<String, dynamic>>()
        .map(SongResult.fromJson)
        .toList();
  }

  Future<List<ChartResult>> charts(int bandId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileBandCharts(bandId),
    );
    final list = response.data!['charts'] as List<dynamic>? ?? [];
    return list
        .cast<Map<String, dynamic>>()
        .map(ChartResult.fromJson)
        .toList();
  }
}

final musicRepositoryProvider = Provider<MusicRepository>((ref) {
  return MusicRepository(ref.watch(apiClientProvider).dio);
});
