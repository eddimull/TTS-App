import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/auth/data/models/band_summary.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/bands/providers/bands_provider.dart';

/// Riverpod notifier exposing the user's personal band and creating one
/// lazily via `POST /api/mobile/bands/solo` when needed.
///
/// The personal band is hidden from band-selector UIs but its bookings/events
/// surface in aggregated lists (Dashboard, Bookings tab) with a personal-
/// treatment chip (user avatar + "Personal").
class PersonalBandNotifier extends Notifier<void> {
  @override
  void build() {}

  /// The user's personal band, derived from [authProvider]. Returns null when
  /// the user has not yet had a personal band created.
  BandSummary? get personalBand {
    final auth = ref.read(authProvider).value;
    if (auth is! AuthAuthenticated) return null;
    for (final band in auth.bands) {
      if (band.isPersonal) return band;
    }
    return null;
  }

  /// Returns the user's personal band, creating one via `POST /bands/solo`
  /// if it does not yet exist. After creation the auth state is refreshed
  /// so the rest of the app sees the new band.
  ///
  /// Throws if the user is not authenticated, or the API call fails.
  Future<BandSummary> ensureExists() async {
    final existing = personalBand;
    if (existing != null) return existing;

    await ref.read(bandsProvider.notifier).goSolo();

    final created = personalBand;
    if (created == null) {
      throw StateError(
        'Personal band creation succeeded but band did not appear in auth state',
      );
    }
    return created;
  }
}

final personalBandProvider =
    NotifierProvider<PersonalBandNotifier, void>(() => PersonalBandNotifier());
