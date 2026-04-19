import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/core_providers.dart';
import '../../auth/data/models/band_summary.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/bands_repository.dart';

final bandsRepositoryProvider = Provider<BandsRepository>((ref) {
  final dio = ref.watch(apiClientProvider).dio;
  return BandsRepository(dio);
});

/// Notifier for band onboarding actions. Each method updates [authProvider]
/// on success so the router guard can react.
class BandsNotifier extends Notifier<void> {
  @override
  void build() {}

  BandsRepository get _repo => ref.read(bandsRepositoryProvider);

  /// Create a band, then (optionally) invite members. Returns the new band.
  Future<BandSummary> createBand(String name, List<String> emails) async {
    final band = await _repo.createBand(name);
    if (emails.isNotEmpty) {
      await _repo.inviteMembers(band.id, emails);
    }
    // Refresh auth so the new band appears in authState.bands
    await ref.read(authProvider.notifier).refreshBands();
    return band;
  }

  /// Accept an invite key and refresh auth bands.
  Future<void> joinBand(String key) async {
    await _repo.joinBand(key);
    await ref.read(authProvider.notifier).refreshBands();
  }

  /// Create a personal band and refresh auth bands.
  Future<void> goSolo() async {
    await _repo.goSolo();
    await ref.read(authProvider.notifier).refreshBands();
  }

  /// Get invite key for QR display.
  Future<String> getInviteKey(int bandId) => _repo.getInviteKey(bandId);
}

final bandsProvider = NotifierProvider<BandsNotifier, void>(() => BandsNotifier());
