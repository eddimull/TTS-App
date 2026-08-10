import 'package:dio/dio.dart';
import '../../../core/network/api_endpoints.dart';
import 'models/help_article.dart';

class HelpRepository {
  HelpRepository(this._dio);
  final Dio _dio;

  Future<HelpIndex> getIndex() async {
    final response = await _dio.get(ApiEndpoints.mobileHelp);
    return HelpIndex.fromJson(response.data as Map<String, dynamic>);
  }

  Future<HelpArticle> getArticle(String slug) async {
    final response = await _dio.get(ApiEndpoints.mobileHelpArticle(slug));
    return HelpArticle.fromJson(
        (response.data as Map<String, dynamic>)['article']
            as Map<String, dynamic>);
  }
}
