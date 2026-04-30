// Smoke test: confirms the test harness wires up correctly and produces a
// runnable widget tree that lands on /login when no token is present.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(stubConnectivityChannel);

  testWidgets('bootstrapApp renders /login with no token', (tester) async {
    final harness = await bootstrapApp(
      handler: (options) async => json(200, {}),
    );

    await tester.pumpWidget(harness.widget);
    await tester.pumpAndSettle();

    expect(find.text('Sign In'), findsOneWidget);
    expect(await harness.storage.readToken(), isNull);
  });

  testWidgets('StubAdapter captures request bodies', (tester) async {
    // This test verifies the capture mechanism in isolation — it builds its
    // own StubAdapter pointing at the harness's capturedBodies map rather
    // than going through the harness's apiClient. That keeps the smoke test
    // short and not coupled to the app's bootstrap behavior.
    final harness = await bootstrapApp(
      handler: (options) async => json(200, {}),
    );

    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = StubAdapter(
        (options) async => json(200, {'ok': true}),
        capturedBodies: harness.capturedBodies,
      );

    // Dio's internal async pipeline involves microtasks/timers that don't
    // advance under testWidgets' fake-async clock without a pump. Run the
    // request in real-async time via tester.runAsync.
    await tester.runAsync(() async {
      await dio.post<Map<String, dynamic>>('/echo', data: {'hello': 'world'});
    });

    expect(harness.capturedBodies['/echo'], isNotNull);
    expect(harness.capturedBodies['/echo']!.first, {'hello': 'world'});
  });
}
