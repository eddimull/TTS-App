// Models for the "Questionnaire → Event routing" review screen.
//
// Hand-written, null-safe `fromJson` factories, matching the preview payload
// from `GET …/questionnaire-instances/{instance}/routing`.

class RoutingItem {
  const RoutingItem({
    required this.responseId,
    required this.fieldLabel,
    required this.valueDisplay,
    required this.target,
    required this.targetLabel,
    this.status = 'pending',
    this.defaultChecked = true,
    this.compatibleTargets = const [],
  });

  final int responseId;
  final String fieldLabel;
  final String valueDisplay;
  final String target;
  final String targetLabel;

  /// Destinations this answer may be re-routed to. Optional in the payload;
  /// when empty the Send-to sheet offers only the current target.
  final List<RoutingTarget> compatibleTargets;

  /// `pending` | `applied` | `stale`.
  final String status;
  final bool defaultChecked;

  bool get isApplied => status == 'applied';
  bool get isStale => status == 'stale';

  factory RoutingItem.fromJson(Map<String, dynamic> json) {
    final rawTargets = json['compatible_targets'];
    return RoutingItem(
      responseId: ((json['response_id'] as num?) ?? 0).toInt(),
      fieldLabel: json['field_label'] as String? ?? '',
      valueDisplay: json['value_display'] as String? ?? '',
      target: json['target'] as String? ?? '',
      targetLabel: json['target_label'] as String? ?? '',
      status: json['status'] as String? ?? 'pending',
      defaultChecked: json['default_checked'] as bool? ?? true,
      compatibleTargets: rawTargets is List
          ? rawTargets
              .map(RoutingTarget.tryParse)
              .whereType<RoutingTarget>()
              .toList()
          : const [],
    );
  }
}

class RoutingGroup {
  const RoutingGroup({
    required this.key,
    required this.label,
    required this.items,
  });

  final String key;
  final String label;
  final List<RoutingItem> items;

  factory RoutingGroup.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    return RoutingGroup(
      key: json['key'] as String? ?? '',
      label: json['label'] as String? ?? '',
      items: raw is List
          ? raw
              .whereType<Map<String, dynamic>>()
              .map(RoutingItem.fromJson)
              .toList()
          : const [],
    );
  }
}

/// A selectable destination for an answer (used by the Send-to sheet).
class RoutingTarget {
  const RoutingTarget({required this.key, required this.label, this.hint});

  final String key;
  final String label;
  final String? hint;

  /// Accepts either a bare key string or `{key, label, hint}`.
  static RoutingTarget? tryParse(dynamic raw) {
    if (raw is String && raw.isNotEmpty) {
      return RoutingTarget(key: raw, label: knownTargetLabel(raw) ?? raw);
    }
    if (raw is Map<String, dynamic>) {
      final key = raw['key'] as String?;
      if (key == null || key.isEmpty) return null;
      return RoutingTarget(
        key: key,
        label: raw['label'] as String? ?? knownTargetLabel(key) ?? key,
        hint: raw['hint'] as String?,
      );
    }
    return null;
  }
}

/// Labels for the targets named in the plan, used when the server sends bare
/// keys and for the fallback list in the Send-to sheet.
String? knownTargetLabel(String key) => _knownTargets[key];

const _knownTargets = <String, String>{
  'wedding.toasts': 'Toasts',
  'wedding.colors': 'Wedding colors',
  'wedding.onsite': 'Ceremony onsite',
  'wedding.outside': 'Partly outdoors',
  'wedding.dance.first': 'First dance',
  'performance.notes': 'Performance notes',
  'event.notes': 'Event notes',
};

/// Free-text destinations offered for an unrouted answer when the server
/// doesn't list compatible ones. Boolean and per-dance targets are left out
/// because they only accept specific field types.
List<RoutingTarget> get fallbackRoutingTargets => [
      for (final k in const [
        'wedding.toasts',
        'wedding.colors',
        'performance.notes',
        'event.notes',
      ])
        RoutingTarget(key: k, label: _knownTargets[k]!),
    ];

class RoutingConflict {
  const RoutingConflict({
    required this.kind,
    this.songId,
    this.title,
    this.bookingValue,
    this.formValue,
    this.resolution,
  });

  static const songBothLists = 'song_both_lists';
  static const venueMismatch = 'venue_mismatch';

  final String kind;
  final int? songId;
  final String? title;
  final String? bookingValue;
  final String? formValue;

  /// Server-side resolution, `must_play` / `do_not_play` (songs) or
  /// `booking` / `form` (venue). Null while unresolved.
  final String? resolution;

  bool get isSong => kind == songBothLists;
  bool get isVenue => kind == venueMismatch;

  /// Stable key used by the selection state.
  String get id => isSong ? 'song:$songId' : kind;

  factory RoutingConflict.fromJson(Map<String, dynamic> json) =>
      RoutingConflict(
        kind: json['kind'] as String? ?? '',
        songId: (json['song_id'] as num?)?.toInt(),
        title: json['title'] as String?,
        bookingValue: json['booking_value'] as String?,
        formValue: json['form_value'] as String?,
        resolution: json['resolution'] as String?,
      );
}

class SongRequests {
  const SongRequests({
    this.mustPlay = 0,
    this.doNotPlay = 0,
    this.writeIns = const [],
  });

  final int mustPlay;
  final int doNotPlay;
  final List<String> writeIns;

  bool get isEmpty => mustPlay == 0 && doNotPlay == 0 && writeIns.isEmpty;

  factory SongRequests.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const SongRequests();
    final raw = json['write_ins'];
    return SongRequests(
      mustPlay: ((json['must_play'] as num?) ?? 0).toInt(),
      doNotPlay: ((json['do_not_play'] as num?) ?? 0).toInt(),
      writeIns: raw is List ? raw.map((e) => '$e').toList() : const [],
    );
  }
}

class RoutingContact {
  const RoutingContact({required this.name, required this.onBooking});

  final String name;
  final bool onBooking;

  factory RoutingContact.fromJson(Map<String, dynamic> json) => RoutingContact(
        name: json['name'] as String? ?? '',
        onBooking: json['on_booking'] as bool? ?? false,
      );
}

/// An answer with no mapping; the user can pick a destination for it.
class UnroutedItem {
  const UnroutedItem({
    required this.responseId,
    required this.fieldLabel,
    required this.valueDisplay,
    this.compatibleTargets = const [],
  });

  final int responseId;
  final String fieldLabel;
  final String valueDisplay;
  final List<RoutingTarget> compatibleTargets;

  factory UnroutedItem.fromJson(Map<String, dynamic> json) {
    final raw = json['compatible_targets'];
    return UnroutedItem(
      responseId: ((json['response_id'] as num?) ?? 0).toInt(),
      fieldLabel: json['field_label'] as String? ?? '',
      valueDisplay: json['value_display'] as String? ?? '',
      compatibleTargets: raw is List
          ? raw.map(RoutingTarget.tryParse).whereType<RoutingTarget>().toList()
          : const [],
    );
  }
}

class RoutingPreview {
  const RoutingPreview({
    this.groups = const [],
    this.conflicts = const [],
    this.songRequests = const SongRequests(),
    this.contacts = const [],
    this.unrouted = const [],
  });

  final List<RoutingGroup> groups;
  final List<RoutingConflict> conflicts;
  final SongRequests songRequests;
  final List<RoutingContact> contacts;
  final List<UnroutedItem> unrouted;

  Iterable<RoutingItem> get allItems => groups.expand((g) => g.items);

  /// Conflict kinds the app knows how to resolve; others are ignored.
  List<RoutingConflict> get knownConflicts =>
      conflicts.where((c) => c.isSong || c.isVenue).toList();

  factory RoutingPreview.fromJson(Map<String, dynamic> json) {
    List<T> list<T>(String key, T Function(Map<String, dynamic>) f) {
      final raw = json[key];
      return raw is List
          ? raw.whereType<Map<String, dynamic>>().map(f).toList()
          : <T>[];
    }

    final rawSongs = json['song_requests'];
    return RoutingPreview(
      groups: list('groups', RoutingGroup.fromJson),
      conflicts: list('conflicts', RoutingConflict.fromJson),
      songRequests: SongRequests.fromJson(
          rawSongs is Map<String, dynamic> ? rawSongs : null),
      contacts: list('contacts', RoutingContact.fromJson),
      unrouted: list('unrouted', UnroutedItem.fromJson),
    );
  }
}

/// Response of `POST …/route`.
class RouteResult {
  const RouteResult({
    required this.applicationId,
    required this.applied,
    this.event = const {},
  });

  final int applicationId;
  final int applied;
  final Map<String, dynamic> event;

  int? get eventId => (event['id'] as num?)?.toInt();
  String? get eventKey => event['key'] as String?;

  factory RouteResult.fromJson(Map<String, dynamic> json) {
    final rawEvent = json['event'];
    return RouteResult(
      applicationId: ((json['application_id'] as num?) ?? 0).toInt(),
      applied: ((json['applied'] as num?) ?? 0).toInt(),
      event: rawEvent is Map<String, dynamic> ? rawEvent : const {},
    );
  }
}
