import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tts_bandmate/features/help/data/help_repository.dart';
import 'package:tts_bandmate/features/help/data/models/help_article.dart';
import 'package:tts_bandmate/features/help/providers/help_providers.dart';
import 'package:tts_bandmate/features/help/screens/help_article_screen.dart';

/// getArticle always fails with the given error — used to pin the screen's
/// error-state rendering (404 vs. generic) independent of a working fetch.
class _FailingHelpRepository implements HelpRepository {
  _FailingHelpRepository(this._error);

  final Object _error;

  @override
  Future<HelpIndex> getIndex() async =>
      const HelpIndex(articles: [], categoryLabels: {});

  @override
  Future<HelpArticle> getArticle(String slug) async => throw _error;
}

DioException _notFoundError(String slug) {
  final requestOptions =
      RequestOptions(path: '/api/mobile/help/$slug');
  return DioException(
    requestOptions: requestOptions,
    response: Response(
      statusCode: 404,
      requestOptions: requestOptions,
    ),
    type: DioExceptionType.badResponse,
  );
}

Future<void> _pumpArticleScreen(
  WidgetTester tester, {
  required HelpRepository repository,
  required String slug,
}) async {
  tester.view.physicalSize = const Size(320, 568);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        helpRepositoryProvider.overrideWithValue(repository),
      ],
      child: CupertinoApp(
        home: HelpArticleScreen(slug: slug),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'HelpArticleScreen shows the friendly not-available state on a 404',
      (tester) async {
    await _pumpArticleScreen(
      tester,
      repository: _FailingHelpRepository(_notFoundError('finances')),
      slug: 'finances',
    );

    expect(find.text("This article isn't available."), findsOneWidget);
    expect(find.text('Back to Help'), findsOneWidget);

    // No raw error dump — the DioException's toString() must not leak
    // through as visible text.
    expect(find.textContaining('DioException'), findsNothing);
    expect(find.textContaining('404'), findsNothing);

    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'HelpArticleScreen shows a generic error state for non-404 failures',
      (tester) async {
    await _pumpArticleScreen(
      tester,
      repository: _FailingHelpRepository(Exception('network down')),
      slug: 'created-a-band',
    );

    expect(find.text("Couldn't load this article."), findsOneWidget);
    expect(find.text('Back to Help'), findsOneWidget);
    expect(find.textContaining('network down'), findsNothing);

    expect(tester.takeException(), isNull);
  });
}
