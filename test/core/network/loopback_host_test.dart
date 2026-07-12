import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/core/network/loopback_host_io.dart';

void main() {
  group('isLoopbackHost', () {
    test('true for "localhost"', () {
      expect(isLoopbackHost('localhost'), isTrue);
    });

    test('true for IPv4 loopback 127.0.0.1', () {
      expect(isLoopbackHost('127.0.0.1'), isTrue);
    });

    test('true for another address in the 127.0.0.0/8 loopback block', () {
      expect(isLoopbackHost('127.0.0.2'), isTrue);
    });

    test('true for IPv6 loopback ::1', () {
      expect(isLoopbackHost('::1'), isTrue);
    });

    test('false for a real hostname', () {
      expect(isLoopbackHost('staging.ttsbandmate.com'), isFalse);
    });

    test('false for a non-loopback IPv4 address', () {
      expect(isLoopbackHost('192.168.1.50'), isFalse);
    });
  });
}
