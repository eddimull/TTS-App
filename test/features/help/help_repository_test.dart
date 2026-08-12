import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/help/data/help_repository.dart';

class _FakeDio extends Fake implements Dio {
  _FakeDio(this._responses);

  final Map<String, dynamic> _responses;

  @override
  Future<Response<T>> get<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onReceiveProgress,
  }) async {
    if (!_responses.containsKey(path)) {
      throw DioException(requestOptions: RequestOptions(path: path));
    }
    return Response<T>(
      data: _responses[path] as T,
      statusCode: 200,
      requestOptions: RequestOptions(path: path),
    );
  }
}

void main() {
  const indexPath = '/api/mobile/help';
  const articlePath = '/api/mobile/help/created-a-band';

  Map<String, dynamic> payload() => {
        indexPath: {
          'articles': [
            {
              'slug': 'created-a-band',
              'title': 'You created a band',
              'category': 'getting-started',
              'platforms': ['web', 'mobile'],
              'order': 10,
              'updated_at': '2026-08-10T12:00:00+00:00',
            },
          ],
          'category_labels': {'getting-started': 'Getting started'},
        },
        articlePath: {
          'article': {
            'slug': 'created-a-band',
            'title': 'You created a band',
            'category': 'getting-started',
            'platforms': ['web', 'mobile'],
            'order': 10,
            'updated_at': '2026-08-10T12:00:00+00:00',
            'markdown': '## Hello',
          },
        },
      };

  group('HelpRepository', () {
    test('getIndex hits /api/mobile/help and parses articles + labels', () async {
      final repo = HelpRepository(_FakeDio(payload()));
      final index = await repo.getIndex();

      expect(index.articles, hasLength(1));
      expect(index.articles.single.slug, 'created-a-band');
      expect(index.categoryLabels['getting-started'], 'Getting started');
    });

    test('getArticle hits /api/mobile/help/{slug} and parses the article', () async {
      final repo = HelpRepository(_FakeDio(payload()));
      final article = await repo.getArticle('created-a-band');

      expect(article.slug, 'created-a-band');
      expect(article.markdown, '## Hello');
    });
  });
}
