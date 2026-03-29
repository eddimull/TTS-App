class UpcomingChart {
  const UpcomingChart({
    required this.type,
    this.chartId,
    required this.title,
    this.composer,
    this.url,
    required this.eventTitle,
    required this.eventDate,
    this.venueName,
  });

  /// "chart" or "song".
  final String type;

  final int? chartId;
  final String title;
  final String? composer;
  final String? url;
  final String eventTitle;

  /// ISO date string, e.g. "2026-04-15".
  final String eventDate;

  final String? venueName;

  factory UpcomingChart.fromJson(Map<String, dynamic> json) {
    return UpcomingChart(
      type: json['type'] as String? ?? 'chart',
      chartId: json['chart_id'] == null
          ? null
          : (json['chart_id'] as num).toInt(),
      title: json['title'] as String,
      composer: json['composer'] as String?,
      url: json['url'] as String?,
      eventTitle: json['event_title'] as String,
      eventDate: json['event_date'] as String,
      venueName: json['venue_name'] as String?,
    );
  }

  @override
  String toString() =>
      'UpcomingChart(type: $type, title: $title, eventTitle: $eventTitle)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UpcomingChart &&
          runtimeType == other.runtimeType &&
          chartId == other.chartId &&
          title == other.title &&
          eventDate == other.eventDate;

  @override
  int get hashCode => Object.hash(chartId, title, eventDate);
}
