import 'package:dio/dio.dart';
import '../../../core/network/api_endpoints.dart';
import 'models/band_detail.dart';
import 'models/band_invitation.dart';
import 'models/band_member.dart';

class BandSettingsRepository {
  BandSettingsRepository(this._dio);

  final Dio _dio;

  Future<BandDetail> getBandDetail(int bandId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileBandDetail(bandId),
    );
    return BandDetail.fromJson(
        response.data!['band'] as Map<String, dynamic>);
  }

  Future<void> updateBandDetail(
    int bandId, {
    required String name,
    required String siteName,
    required String address,
    required String city,
    required String state,
    required String zip,
  }) async {
    await _dio.patch<void>(
      ApiEndpoints.mobileBandDetail(bandId),
      data: {
        'name': name,
        'site_name': siteName,
        'address': address,
        'city': city,
        'state': state,
        'zip': zip,
      },
    );
  }

  Future<void> uploadLogo(int bandId, List<int> bytes, String filename) async {
    final formData = FormData.fromMap({
      'logo': MultipartFile.fromBytes(bytes, filename: filename),
    });
    await _dio.post<void>(
      ApiEndpoints.mobileBandLogo(bandId),
      data: formData,
    );
  }

  Future<List<BandMember>> getMembers(int bandId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileBandMembers(bandId),
    );
    final list = response.data!['members'] as List<dynamic>;
    return list
        .map((m) => BandMember.fromJson(m as Map<String, dynamic>))
        .toList();
  }

  Future<void> removeMember(int bandId, int userId) async {
    await _dio.delete<void>(
      ApiEndpoints.mobileBandMember(bandId, userId),
    );
  }

  Future<void> setPermission(
    int bandId,
    int userId, {
    required String permission,
    required bool granted,
  }) async {
    await _dio.patch<void>(
      ApiEndpoints.mobileBandMemberPermissions(bandId, userId),
      data: {'permission': permission, 'granted': granted},
    );
  }

  Future<List<BandInvitation>> getInvitations(int bandId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileBandInvitations(bandId),
    );
    final list = response.data!['invitations'] as List<dynamic>;
    return list
        .map((i) => BandInvitation.fromJson(i as Map<String, dynamic>))
        .toList();
  }

  Future<void> revokeInvitation(int bandId, int invitationId) async {
    await _dio.delete<void>(
      ApiEndpoints.mobileBandInvitation(bandId, invitationId),
    );
  }
}
