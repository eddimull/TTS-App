import 'queue_entry.dart';

class SessionCaptain {
  const SessionCaptain({required this.userId, this.name});

  final int userId;
  final String? name;

  factory SessionCaptain.fromJson(Map<String, dynamic> json) => SessionCaptain(
        userId: json['user_id'] as int,
        name: json['name'] as String?,
      );
}

class LiveSession {
  const LiveSession({
    required this.id,
    required this.status,
    required this.isDynamic,
    required this.currentPosition,
    this.startedAt,
    this.breakStartedAt,
    required this.afterBreak,
    required this.queue,
    required this.captains,
  });

  final int id;
  final String status; // 'active' | 'paused' | 'break' | 'completed'
  final bool isDynamic;
  final int currentPosition;
  final String? startedAt;
  final String? breakStartedAt;
  final bool afterBreak;
  final List<QueueEntry> queue;
  final List<SessionCaptain> captains;

  bool get isActive => status == 'active';
  bool get isOnBreak => status == 'break';
  bool get isCompleted => status == 'completed';

  QueueEntry? get currentSong => queue
      .where((e) => e.position == currentPosition && e.isPending && !e.isBreak)
      .firstOrNull;

  QueueEntry? get nextSong => queue
      .where((e) => e.position > currentPosition && e.isPending && !e.isBreak)
      .toList()
      .firstOrNull;

  factory LiveSession.fromJson(Map<String, dynamic> json) => LiveSession(
        id: json['id'] as int,
        status: json['status'] as String? ?? 'active',
        isDynamic: json['is_dynamic'] as bool? ?? false,
        currentPosition: json['current_position'] as int? ?? 0,
        startedAt: json['started_at'] as String?,
        breakStartedAt: json['break_started_at'] as String?,
        afterBreak: json['after_break'] as bool? ?? false,
        queue: (json['queue'] as List<dynamic>? ?? [])
            .map((e) => QueueEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        captains: (json['captains'] as List<dynamic>? ?? [])
            .map((e) => SessionCaptain.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  LiveSession copyWith({
    String? status,
    int? currentPosition,
    String? breakStartedAt,
    bool? afterBreak,
    List<QueueEntry>? queue,
    List<SessionCaptain>? captains,
  }) =>
      LiveSession(
        id: id,
        status: status ?? this.status,
        isDynamic: isDynamic,
        currentPosition: currentPosition ?? this.currentPosition,
        startedAt: startedAt,
        breakStartedAt: breakStartedAt ?? this.breakStartedAt,
        afterBreak: afterBreak ?? this.afterBreak,
        queue: queue ?? this.queue,
        captains: captains ?? this.captains,
      );
}
