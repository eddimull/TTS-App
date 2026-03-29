import 'rehearsal_summary.dart';

class RehearsalSchedule {
  const RehearsalSchedule({
    required this.id,
    required this.name,
    this.description,
    this.frequency,
    this.locationName,
    this.locationAddress,
    required this.active,
    required this.upcomingRehearsals,
  });

  final int id;
  final String name;
  final String? description;
  final String? frequency;
  final String? locationName;
  final String? locationAddress;
  final bool active;
  final List<RehearsalSummary> upcomingRehearsals;

  factory RehearsalSchedule.fromJson(Map<String, dynamic> json) {
    final rawRehearsals = json['upcoming_rehearsals'];
    final upcomingRehearsals = rawRehearsals is List
        ? rawRehearsals
            .cast<Map<String, dynamic>>()
            .map(RehearsalSummary.fromJson)
            .toList()
        : <RehearsalSummary>[];

    return RehearsalSchedule(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String,
      description: json['description'] as String?,
      frequency: json['frequency'] as String?,
      locationName: json['location_name'] as String?,
      locationAddress: json['location_address'] as String?,
      active: (json['active'] as bool?) ?? true,
      upcomingRehearsals: upcomingRehearsals,
    );
  }

  @override
  String toString() =>
      'RehearsalSchedule(id: $id, name: $name, active: $active)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RehearsalSchedule &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
