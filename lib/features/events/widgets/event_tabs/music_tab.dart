import 'package:flutter/cupertino.dart';

import '../../data/models/event_detail.dart';
import '../event_sections/performance_section.dart';
import '../event_sections/section_primitives.dart';
import '../event_sections/wedding_section.dart';

/// Music tab (interim layout): performance notes, songs and charts, the
/// join-live button while a session is running, and special dances.
class MusicTab extends StatelessWidget {
  const MusicTab({super.key, required this.event});
  final EventDetail event;

  @override
  Widget build(BuildContext context) {
    final perf = event.performance;
    final hasPerformance = perf != null &&
        ((perf.notes?.isNotEmpty ?? false) ||
            perf.songs.isNotEmpty ||
            perf.charts.isNotEmpty);
    final dances = event.wedding?.dances ?? const <WeddingDance>[];

    final blocks = <Widget>[
      // State-driven CTA: only while a live session is running. The plain
      // Setlist row lives in the ⋯ menu.
      if (event.liveSessionId != null) LiveSetlistButton(eventKey: event.key),
      if (hasPerformance) ...[
        const SectionHeader(title: 'Performance'),
        const SizedBox(height: 8),
        PerformanceSection(performance: perf),
      ],
      if (dances.isNotEmpty) ...[
        const SectionHeader(title: 'Special dances'),
        const SizedBox(height: 8),
        WeddingSection(wedding: WeddingDetail(dances: dances)),
      ],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < blocks.length; i++) ...[
          if (i > 0) const SizedBox(height: 20),
          blocks[i],
        ],
      ],
    );
  }
}
