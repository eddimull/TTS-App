import 'package:dio/dio.dart';
import '../../../core/network/api_endpoints.dart';
import '../../auth/data/models/band_summary.dart';

class BandsRepository {
  BandsRepository(this._dio);

  final Dio _dio;

  /// Create a new band. Returns the new band's id and name.
  Future<BandSummary> createBand(String name) async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.mobileCreateBand,
      data: {'name': name},
    );
    final band = response.data!['band'] as Map<String, dynamic>;
    return BandSummary.fromJson(band);
  }

  /// Send member invitations for [bandId] to each email in [emails].
  Future<void> inviteMembers(int bandId, List<String> emails) async {
    await _dio.post<void>(
      ApiEndpoints.mobileBandInvite(bandId),
      data: {'emails': emails},
    );
  }

  /// Accept an invite by [key]. Returns updated bands list.
  Future<List<BandSummary>> joinBand(String key) async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.mobileBandsJoin,
      data: {'key': key},
    );
    final bandList = (response.data!['bands'] as List<dynamic>)
        .map((b) => BandSummary.fromJson(b as Map<String, dynamic>))
        .toList();
    return bandList;
  }

  /// Create a personal auto-band. Returns updated bands list.
  Future<List<BandSummary>> goSolo() async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.mobileBandsSolo,
    );
    final bandList = (response.data!['bands'] as List<dynamic>)
        .map((b) => BandSummary.fromJson(b as Map<String, dynamic>))
        .toList();
    return bandList;
  }

  /// Get the raw invite key for [bandId] to render as QR.
  Future<String> getInviteKey(int bandId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileBandInviteQr(bandId),
    );
    return response.data!['key'] as String;
  }
}
