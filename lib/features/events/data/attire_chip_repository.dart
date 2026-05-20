import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/core_providers.dart';
import 'models/attire_chip.dart';

/// Performs CRUD operations against `/api/mobile/bands/{band}/attire-chips`.
///
/// The `{band}` segment is populated from the `X-Band-ID` header that
/// [apiClientProvider] already attaches — the bandId is still threaded through
/// here explicitly so the URL is formed correctly and so that [ProviderContainer]
/// overrides in tests can swap out the repo per-band.
class AttireChipRepository {
  AttireChipRepository(this._dio);

  final Dio _dio;

  /// Fetches all attire chips for [bandId], ordered by position then label.
  ///
  /// Returns an empty list when the band has no chips yet; the provider layer
  /// substitutes the six hardcoded defaults in that case.
  Future<List<AttireChip>> list(int bandId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileBandAttireChips(bandId),
    );
    final raw = (response.data!['data'] as List<dynamic>?) ?? [];
    return raw.cast<Map<String, dynamic>>().map(AttireChip.fromJson).toList();
  }

  /// Creates a new chip with [label] under [bandId].
  ///
  /// Idempotent on duplicate labels — the backend returns the existing chip.
  /// The backend also seeds the six default labels on the *first* POST, so
  /// callers should refresh the list after this resolves.
  Future<AttireChip> create(int bandId, String label) async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.mobileBandAttireChips(bandId),
      data: {'label': label},
    );
    final chipJson = response.data!['data'] as Map<String, dynamic>;
    return AttireChip.fromJson(chipJson);
  }

  /// Deletes the chip with [chipId] under [bandId]. Expects 204 on success.
  Future<void> delete(int bandId, int chipId) async {
    await _dio.delete<void>(
      ApiEndpoints.mobileBandAttireChip(bandId, chipId),
    );
  }
}

final attireChipRepositoryProvider = Provider<AttireChipRepository>((ref) {
  return AttireChipRepository(ref.watch(apiClientProvider).dio);
});
