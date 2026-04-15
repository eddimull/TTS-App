import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'app.dart';

// Don't retry on definitive server errors (4xx). Only retry on network
// failures or 5xx where a retry might succeed.
Duration? _retryPolicy(int retryCount, Object error) {
  if (error is DioException && error.response != null) return null;
  // Exponential backoff: 200ms, 400ms, 800ms, …
  return Duration(milliseconds: 200 * (1 << retryCount));
}

Future<void> main() async {
  await SentryFlutter.init(
    (options) {
      options.dsn = const String.fromEnvironment('SENTRY_DSN');
      options.environment = const String.fromEnvironment(
        'SENTRY_ENVIRONMENT',
        defaultValue: 'development',
      );
      options.tracesSampleRate = 1.0;
      options.profilesSampleRate = 1.0;
      options.attachScreenshot = true;
      options.attachViewHierarchy = true;
    },
    appRunner: () => runApp(
      ProviderScope(retry: _retryPolicy, child: const BandmateApp()),
    ),
  );
}
