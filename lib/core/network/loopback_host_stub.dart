/// Web stub: there is no dev-loopback TLS bypass concept in a browser (the
/// browser's own cert store applies), so this always returns false. See
/// `loopback_host_io.dart` for the native impl.
bool isLoopbackHost(String host) => false;
