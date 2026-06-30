class PlannerPlanItem {
  const PlannerPlanItem({this.songId, required this.title, required this.reason});

  final int? songId;
  final String title;
  final String reason;

  factory PlannerPlanItem.fromJson(Map<String, dynamic> json) => PlannerPlanItem(
        songId: (json['song_id'] as num?)?.toInt(),
        title: json['title'] as String? ?? '',
        reason: json['reason'] as String? ?? '',
      );
}

class PlannerPlan {
  const PlannerPlan({required this.title, required this.items});

  final String title;
  final List<PlannerPlanItem> items;

  factory PlannerPlan.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    final items = raw is List
        ? raw.cast<Map<String, dynamic>>().map(PlannerPlanItem.fromJson).toList()
        : <PlannerPlanItem>[];
    return PlannerPlan(title: json['title'] as String? ?? 'Rehearsal plan', items: items);
  }
}
