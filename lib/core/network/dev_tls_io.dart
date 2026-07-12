import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';

import 'loopback_host.dart';

/// Native (non-web) impl. In DEBUG builds only, accept self-signed /
/// untrusted certs **for loopback hosts only**, so the app can talk to a
/// local HTTPS dev server (e.g. an mkcert cert the device doesn't trust)
/// without disabling TLS verification for staging/prod hosts a debug build
/// might also reach. Compiled out of release builds entirely.
void configureDevTls(Dio dio) {
  if (!kDebugMode) return;
  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () {
      final client = HttpClient();
      client.badCertificateCallback =
          (cert, host, port) => isLoopbackHost(host);
      return client;
    },
  );
}
