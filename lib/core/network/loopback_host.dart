// Shared loopback-host predicate. Resolves to the native impl
// (loopback_host_io.dart) on platforms that have dart:io, and to a stub that
// always returns false on web (there is no dev-loopback TLS bypass concept in
// a browser — the browser's own cert store applies) — so importing this
// never drags dart:io into a web build.
export 'loopback_host_stub.dart' if (dart.library.io) 'loopback_host_io.dart';
