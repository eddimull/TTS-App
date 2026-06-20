/// A single entry in a band's substitute call list for a given role/instrument.
///
/// Mirrors the web `SubstituteCallListController@index` payload (grouped by
/// instrument). An entry is either a roster member (`rosterMemberId` set) or a
/// custom person (`isCustom`), and carries a `priority` for call order.
class CallListEntry {
  const CallListEntry({
    required this.id,
    required this.bandId,
    required this.instrument,
    required this.priority,
    this.bandRoleId,
    this.rosterMemberId,
    this.name,
    this.email,
    this.phone,
    this.notes,
  });

  final int id;
  final int bandId;

  /// Instrument label (the group key), e.g. "Guitar".
  final String instrument;
  final int priority;
  final int? bandRoleId;
  final int? rosterMemberId;

  /// Display name (from roster member or custom_name).
  final String? name;
  final String? email;
  final String? phone;
  final String? notes;

  bool get isCustom => rosterMemberId == null;

  factory CallListEntry.fromJson(Map<String, dynamic> json) {
    // The web index maps roster-member entries with a nested `roster_member`
    // object and custom entries with `custom_*` fields. Resolve a display
    // name/email/phone from whichever is present.
    final rosterMember = json['roster_member'] as Map<String, dynamic>?;
    return CallListEntry(
      id: (json['id'] as num).toInt(),
      bandId: (json['band_id'] as num?)?.toInt() ?? 0,
      instrument: json['instrument'] as String? ?? '',
      priority: (json['priority'] as num?)?.toInt() ?? 0,
      bandRoleId: (json['band_role_id'] as num?)?.toInt(),
      rosterMemberId: (json['roster_member_id'] as num?)?.toInt(),
      name: rosterMember?['display_name'] as String? ??
          json['custom_name'] as String?,
      email: rosterMember?['display_email'] as String? ??
          json['custom_email'] as String?,
      phone: rosterMember?['phone'] as String? ??
          json['custom_phone'] as String?,
      notes: json['notes'] as String?,
    );
  }
}

/// Call list entries grouped under one instrument heading.
class CallListGroup {
  const CallListGroup({required this.instrument, required this.entries});

  final String instrument;
  final List<CallListEntry> entries;
}
