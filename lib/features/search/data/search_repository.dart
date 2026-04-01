import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tts_bandmate/core/providers/core_providers.dart';
import 'models/search_models.dart';

class SearchRepository {
  SearchRepository(this._dio);

  final Dio _dio;

  Future<SearchResults> search(String query) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileSearch,
      queryParameters: {'q': query},
    );
    return SearchResults.fromJson(response.data!);
  }
}

final searchRepositoryProvider = Provider<SearchRepository>((ref) {
  return SearchRepository(ref.watch(apiClientProvider).dio);
});
