/// Shared Android notification channel constants. Kept dependency-light (no
/// flutter_local_notifications import) so the background isolate handler in
/// `main.dart` — which cannot touch [PushService]'s instance state — and the
/// foreground [PushService] both build notifications from the same identity.
class BandUpdatesChannel {
  static const id = 'band_updates';
  static const name = 'Band Updates';
  static const description = "Changes to your band's schedule and activity";
}
