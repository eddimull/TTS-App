import 'dart:io';

/// True when [host] is a loopback address (localhost / 127.0.0.1 / ::1).
/// Used to scope debug-only, self-signed-cert TLS bypasses (see
/// `dev_tls_io.dart` and `main.dart`'s `HttpOverrides`) to the local dev
/// server only, never to staging/prod hosts a debug build might also reach.
bool isLoopbackHost(String host) {
  if (host == 'localhost') return true;
  final addr = InternetAddress.tryParse(host);
  return addr != null && addr.isLoopback;
}
