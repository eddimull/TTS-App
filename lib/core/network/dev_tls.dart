// Debug-only TLS configuration for reaching a local HTTPS dev server.
//
// Resolves to the native impl (dev_tls_io.dart) on platforms that have
// dart:io, and to a no-op stub (dev_tls_stub.dart) on web — so importing
// ApiClient never drags dart:io into a web build.
export 'dev_tls_stub.dart' if (dart.library.io) 'dev_tls_io.dart';
