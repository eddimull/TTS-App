import 'planner_plan.dart';

class PlannerMessage {
  const PlannerMessage({
    required this.id,
    required this.role,
    required this.text,
    this.suggestions = const [],
    this.plan,
    this.status = 'complete',
  });

  final int id;
  final String role;      // 'user' | 'assistant'
  final String text;
  final List<String> suggestions;
  final PlannerPlan? plan;
  final String status;    // 'streaming' | 'complete' | 'failed'

  bool get isUser => role == 'user';

  factory PlannerMessage.fromJson(Map<String, dynamic> json) {
    final payload = json['payload'];
    final payloadMap = payload is Map<String, dynamic> ? payload : const <String, dynamic>{};

    final rawSuggestions = payloadMap['suggestions'];
    final suggestions = rawSuggestions is List ? rawSuggestions.cast<String>().toList() : <String>[];

    final rawPlan = payloadMap['plan'];
    final plan = rawPlan is Map<String, dynamic> ? PlannerPlan.fromJson(rawPlan) : null;

    return PlannerMessage(
      id: (json['id'] as num).toInt(),
      role: json['role'] as String? ?? 'assistant',
      text: json['content'] as String? ?? '',
      suggestions: suggestions,
      plan: plan,
      status: json['status'] as String? ?? 'complete',
    );
  }

  PlannerMessage copyWith({
    String? text,
    List<String>? suggestions,
    PlannerPlan? plan,
    String? status,
  }) =>
      PlannerMessage(
        id: id,
        role: role,
        text: text ?? this.text,
        suggestions: suggestions ?? this.suggestions,
        plan: plan ?? this.plan,
        status: status ?? this.status,
      );
}
