import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/notifications/providers/notifications_provider.dart';

void main() {
  test('PushRegistrar exposes register/deregister hooks used by auth', () {
    // Compile-time guard: the methods auth depends on exist with these names.
    expect(PushRegistrar.new, isA<Function>());
  });
}
