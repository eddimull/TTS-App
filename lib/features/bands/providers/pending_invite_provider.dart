import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Holds an invite key captured from a deep link while the user was NOT yet
/// authenticated. Consumed once, after successful auth, to auto-join the band.
class PendingInviteKey extends Notifier<String?> {
  @override
  String? build() => null;

  /// Stash a key to be consumed after authentication.
  void set(String key) => state = key;

  /// Return the pending key (if any) and clear it. Returns null if none.
  String? consume() {
    final key = state;
    state = null;
    return key;
  }
}

final pendingInviteKeyProvider =
    NotifierProvider<PendingInviteKey, String?>(PendingInviteKey.new);
