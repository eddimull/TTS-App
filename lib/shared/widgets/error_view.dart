import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';

import '../../core/network/network_failure.dart';

class ErrorView extends StatelessWidget {
  const ErrorView({
    super.key,
    required this.message,
    this.onRetry,
  });

  final String message;
  final VoidCallback? onRetry;

  /// Copy shown when the app couldn't reach the server at all.
  static const String offlineMessage =
      "You're offline. Reconnect and try again.";

  /// Extracts a human-readable message from an error.
  ///
  /// A transport failure gets connectivity copy — it says nothing about the
  /// request itself, and `DioException.toString()` on a dead network is a wall
  /// of stack-trace-flavoured noise. Otherwise the response body's `message`
  /// field, then a plain fallback.
  static String friendlyMessage(Object e) {
    if (e is DioException) {
      if (isNetworkFailure(e)) return offlineMessage;
      final data = e.response?.data;
      if (data is Map) {
        final msg = data['message'];
        if (msg is String && msg.isNotEmpty) return msg;
      }
      return 'Something went wrong. Please try again.';
    }
    return e.toString();
  }

  @override
  Widget build(BuildContext context) {
    final isOffline = message == offlineMessage;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isOffline
                  ? CupertinoIcons.wifi_slash
                  : CupertinoIcons.exclamationmark_circle,
              size: 48,
              color: isOffline
                  ? CupertinoColors.systemGrey
                  : CupertinoColors.systemRed,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(fontSize: 15),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 24),
              CupertinoButton.filled(
                onPressed: onRetry,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(CupertinoIcons.refresh, size: 18),
                    SizedBox(width: 6),
                    Text('Retry'),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
