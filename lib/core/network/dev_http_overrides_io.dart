import 'dart:io';

import 'package:flutter/foundation.dart';

import 'loopback_host.dart';

/// Install a debug-only, loopback-only [HttpOverrides] so any HTTP client
/// built on top of `dart:io`'s default `HttpClient` (e.g. the one
/// `CachedNetworkImage` creates internally) accepts the local mkcert dev
/// server's self-signed certificate, exactly like `dev_tls_io.dart` already
/// does for Dio. No-op in release builds and for any non-loopback host —
/// staging/prod TLS verification is never weakened.
void installDevHttpOverrides() {
  if (!kDebugMode) return;
  HttpOverrides.global = _DevHttpOverrides();
}

class _DevHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.badCertificateCallback = (cert, host, port) => isLoopbackHost(host);
    return client;
  }
}
