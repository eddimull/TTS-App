import 'package:dio/dio.dart';
import '../../../core/network/api_endpoints.dart';
import 'models/band_role.dart';
import 'models/band_sub.dart';
import 'models/call_list_entry.dart';
import 'models/roster.dart';

class PersonnelRepository {
  PersonnelRepository(this._dio);

  final Dio _dio;

  // ── Roles ──────────────────────────────────────────────────────────────────

  Future<List<BandRole>> getRoles(int bandId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileBandRoles(bandId),
    );
    final list = response.data!['roles'] as List<dynamic>;
    return list
        .map((r) => BandRole.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<BandRole> createRole(int bandId, {required String name}) async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.mobileBandRoles(bandId),
      data: {'name': name},
    );
    return BandRole.fromJson(response.data!['role'] as Map<String, dynamic>);
  }

  Future<BandRole> updateRole(
    int bandId,
    int roleId, {
    String? name,
    bool? isActive,
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      ApiEndpoints.mobileBandRole(bandId, roleId),
      data: {
        if (name != null) 'name': name,
        if (isActive != null) 'is_active': isActive,
      },
    );
    return BandRole.fromJson(response.data!['role'] as Map<String, dynamic>);
  }

  Future<void> deleteRole(int bandId, int roleId) async {
    await _dio.delete<void>(ApiEndpoints.mobileBandRole(bandId, roleId));
  }

  Future<void> reorderRoles(
    int bandId,
    List<({int id, int displayOrder})> order,
  ) async {
    await _dio.post<void>(
      ApiEndpoints.mobileBandRolesReorder(bandId),
      data: {
        'roles': order.map((e) => {'id': e.id, 'display_order': e.displayOrder}).toList(),
      },
    );
  }

  // ── Rosters ────────────────────────────────────────────────────────────────

  Future<List<Roster>> getRosters(int bandId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileBandRosters(bandId),
    );
    final list = response.data!['rosters'] as List<dynamic>;
    return list
        .map((r) => Roster.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<Roster> getRoster(int bandId, int rosterId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileBandRoster(bandId, rosterId),
    );
    return Roster.fromJson(response.data!['roster'] as Map<String, dynamic>);
  }

  Future<Roster> createRoster(
    int bandId, {
    required String name,
    String? description,
    bool? isDefault,
    bool? isActive,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.mobileBandRosters(bandId),
      data: {
        'name': name,
        if (description != null) 'description': description,
        if (isDefault != null) 'is_default': isDefault,
        if (isActive != null) 'is_active': isActive,
      },
    );
    return Roster.fromJson(response.data!['roster'] as Map<String, dynamic>);
  }

  Future<Roster> updateRoster(
    int bandId,
    int rosterId, {
    String? name,
    String? description,
    bool? isDefault,
    bool? isActive,
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      ApiEndpoints.mobileBandRoster(bandId, rosterId),
      data: {
        if (name != null) 'name': name,
        if (description != null) 'description': description,
        if (isDefault != null) 'is_default': isDefault,
        if (isActive != null) 'is_active': isActive,
      },
    );
    return Roster.fromJson(response.data!['roster'] as Map<String, dynamic>);
  }

  Future<void> deleteRoster(int bandId, int rosterId) async {
    await _dio.delete<void>(ApiEndpoints.mobileBandRoster(bandId, rosterId));
  }

  Future<void> setDefaultRoster(int bandId, int rosterId) async {
    await _dio.post<void>(
      ApiEndpoints.mobileBandRosterSetDefault(bandId, rosterId),
    );
  }

  Future<void> initializeRosters(int bandId) async {
    await _dio.post<void>(ApiEndpoints.mobileBandRostersInitialize(bandId));
  }

  // ── Slots ──────────────────────────────────────────────────────────────────

  Future<RosterSlot> createSlot(
    int bandId,
    int rosterId, {
    required String name,
    int? bandRoleId,
    bool? isRequired,
    int? quantity,
    String? notes,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.mobileBandRosterSlots(bandId, rosterId),
      data: {
        'name': name,
        if (bandRoleId != null) 'band_role_id': bandRoleId,
        if (isRequired != null) 'is_required': isRequired,
        if (quantity != null) 'quantity': quantity,
        if (notes != null) 'notes': notes,
      },
    );
    return RosterSlot.fromJson(response.data!['slot'] as Map<String, dynamic>);
  }

  Future<RosterSlot> updateSlot(
    int bandId,
    int slotId, {
    String? name,
    int? bandRoleId,
    bool? isRequired,
    int? quantity,
    String? notes,
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      ApiEndpoints.mobileBandRosterSlot(bandId, slotId),
      data: {
        if (name != null) 'name': name,
        if (bandRoleId != null) 'band_role_id': bandRoleId,
        if (isRequired != null) 'is_required': isRequired,
        if (quantity != null) 'quantity': quantity,
        if (notes != null) 'notes': notes,
      },
    );
    return RosterSlot.fromJson(response.data!['slot'] as Map<String, dynamic>);
  }

  Future<void> deleteSlot(int bandId, int slotId) async {
    await _dio.delete<void>(ApiEndpoints.mobileBandRosterSlot(bandId, slotId));
  }

  // ── Roster Members ─────────────────────────────────────────────────────────

  Future<RosterMember> addRosterMember(
    int bandId,
    int rosterId, {
    int? userId,
    int? slotId,
    String? name,
    String? email,
    String? phone,
    String? role,
    int? bandRoleId,
    String? notes,
    bool? isActive,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.mobileBandRosterMembers(bandId, rosterId),
      data: {
        if (userId != null) 'user_id': userId,
        if (slotId != null) 'slot_id': slotId,
        if (name != null) 'name': name,
        if (email != null) 'email': email,
        if (phone != null) 'phone': phone,
        if (role != null) 'role': role,
        if (bandRoleId != null) 'band_role_id': bandRoleId,
        if (notes != null) 'notes': notes,
        if (isActive != null) 'is_active': isActive,
      },
    );
    return RosterMember.fromJson(
        response.data!['member'] as Map<String, dynamic>);
  }

  Future<RosterMember> updateRosterMember(
    int bandId,
    int memberId, {
    int? slotId,
    String? name,
    String? email,
    String? phone,
    String? role,
    int? bandRoleId,
    String? notes,
    bool? isActive,
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      ApiEndpoints.mobileBandRosterMember(bandId, memberId),
      data: {
        if (slotId != null) 'slot_id': slotId,
        if (name != null) 'name': name,
        if (email != null) 'email': email,
        if (phone != null) 'phone': phone,
        if (role != null) 'role': role,
        if (bandRoleId != null) 'band_role_id': bandRoleId,
        if (notes != null) 'notes': notes,
        if (isActive != null) 'is_active': isActive,
      },
    );
    return RosterMember.fromJson(
        response.data!['member'] as Map<String, dynamic>);
  }

  Future<void> removeRosterMember(int bandId, int memberId) async {
    await _dio.delete<void>(
        ApiEndpoints.mobileBandRosterMember(bandId, memberId));
  }

  Future<RosterMember> toggleRosterMemberActive(
      int bandId, int memberId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.mobileBandRosterMemberToggleActive(bandId, memberId),
    );
    return RosterMember.fromJson(
        response.data!['member'] as Map<String, dynamic>);
  }

  // ── Substitute Call Lists ────────────────────────────────────────────────────

  /// Fetches the band's call lists grouped by instrument.
  Future<List<CallListGroup>> getCallLists(int bandId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileBandCallLists(bandId),
    );
    // `call_lists` is a map keyed by instrument → list of entries.
    final raw = (response.data!['call_lists'] as Map<dynamic, dynamic>?) ?? {};
    final groups = raw.entries.map((e) {
      final entries = (e.value as List<dynamic>)
          .map((j) => CallListEntry.fromJson(j as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.priority.compareTo(b.priority));
      return CallListGroup(instrument: e.key as String, entries: entries);
    }).toList()
      ..sort((a, b) => a.instrument.compareTo(b.instrument));
    return groups;
  }

  /// Adds a custom person to the call list. By default this also sends a
  /// band-level substitute invitation (set [sendInvite] = false to skip).
  Future<CallListEntry> addCallListEntry(
    int bandId, {
    String? instrument,
    int? bandRoleId,
    int? rosterMemberId,
    String? customName,
    String? customEmail,
    String? customPhone,
    String? notes,
    bool sendInvite = true,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.mobileBandCallLists(bandId),
      data: {
        if (instrument != null) 'instrument': instrument,
        if (bandRoleId != null) 'band_role_id': bandRoleId,
        if (rosterMemberId != null) 'roster_member_id': rosterMemberId,
        if (customName != null) 'custom_name': customName,
        if (customEmail != null) 'custom_email': customEmail,
        if (customPhone != null) 'custom_phone': customPhone,
        if (notes != null) 'notes': notes,
        'send_invite': sendInvite,
      },
    );
    return CallListEntry.fromJson(
        response.data!['entry'] as Map<String, dynamic>);
  }

  Future<void> deleteCallListEntry(int bandId, int entryId) async {
    await _dio.delete<void>(ApiEndpoints.mobileBandCallList(bandId, entryId));
  }

  /// Reorders the call list for one instrument. [orderedIds] is the desired
  /// order; priorities are assigned 1..n in that order by the server.
  Future<void> reorderCallList(
    int bandId, {
    required String instrument,
    required List<int> orderedIds,
  }) async {
    await _dio.post<void>(
      ApiEndpoints.mobileBandCallListsReorder(bandId),
      data: {'instrument': instrument, 'order': orderedIds},
    );
  }

  // ── Band Subs ────────────────────────────────────────────────────────────────

  Future<List<BandSub>> getBandSubs(int bandId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileBandSubs(bandId),
    );
    final list = response.data!['subs'] as List<dynamic>;
    return list
        .map((s) => BandSub.fromJson(s as Map<String, dynamic>))
        .toList();
  }

  Future<BandSub> inviteBandSub(
    int bandId, {
    required String email,
    String? name,
    String? phone,
    int? bandRoleId,
    String? notes,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.mobileBandSubInvite(bandId),
      data: {
        'email': email,
        if (name != null) 'name': name,
        if (phone != null) 'phone': phone,
        if (bandRoleId != null) 'band_role_id': bandRoleId,
        if (notes != null) 'notes': notes,
      },
    );
    return BandSub.fromJson(
        response.data!['invitation'] as Map<String, dynamic>);
  }

  /// Revokes a pending band-level invitation.
  Future<void> revokeBandSubInvitation(int bandId, int invitationId) async {
    await _dio.delete<void>(
        ApiEndpoints.mobileBandSubInvitation(bandId, invitationId));
  }

  /// Removes an active band-sub link for [userId].
  Future<void> removeBandSub(int bandId, int userId) async {
    await _dio.delete<void>(ApiEndpoints.mobileBandSubUser(bandId, userId));
  }
}
