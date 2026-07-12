// Debug-only global HttpOverrides so non-Dio HTTP clients (e.g.
// CachedNetworkImage's own HttpClient, used by AuthThumbnail/BandAvatar) also
// accept the local mkcert dev server's self-signed cert for loopback hosts —
// mirroring the bypass `dev_tls_io.dart` already gives Dio. Without this,
// image fetches against a local HTTPS backend fail with a cert error even
// though Dio requests to the same host succeed.
//
// Resolves to the native impl (dev_http_overrides_io.dart) on platforms that
// have dart:io, and to a no-op stub on web — so importing it from main.dart
// never drags dart:io into a web build.
export 'dev_http_overrides_stub.dart'
    if (dart.library.io) 'dev_http_overrides_io.dart';
