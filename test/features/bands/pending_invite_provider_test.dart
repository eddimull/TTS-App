import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bands/providers/pending_invite_provider.dart';

void main() {
  test('starts empty', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(pendingInviteKeyProvider), isNull);
  });

  test('set stores the key; state reflects it', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(pendingInviteKeyProvider.notifier).set('abc123');
    expect(c.read(pendingInviteKeyProvider), 'abc123');
  });

  test('consume returns the key and clears state', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(pendingInviteKeyProvider.notifier).set('abc123');
    final consumed = c.read(pendingInviteKeyProvider.notifier).consume();
    expect(consumed, 'abc123');
    expect(c.read(pendingInviteKeyProvider), isNull);
  });

  test('consume on empty returns null', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(pendingInviteKeyProvider.notifier).consume(), isNull);
  });
}
