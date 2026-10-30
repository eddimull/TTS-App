import 'package:flutter/cupertino.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';
import 'package:tts_bandmate/features/events/data/models/event_detail.dart';
import 'package:tts_bandmate/features/events/widgets/event_sections/section_primitives.dart';

/// "Event details" card for events without a wedding block: backline,
/// production and outdoors. Attire stays in the at-a-glance card. Each row
/// renders only when the event tracks that field.
class EventDetailsCard extends StatelessWidget {
  const EventDetailsCard({super.key, required this.event});
  final EventDetail event;

  static bool hasContent(EventDetail event) =>
      event.backlineProvided != null ||
      event.productionNeeded != null ||
      event.outside != null;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      if (event.backlineProvided != null)
        ('Backline', event.backlineProvided! ? 'Provided' : 'Not provided'),
      if (event.productionNeeded != null)
        ('Production', event.productionNeeded! ? 'Needed' : 'Not needed'),
      if (event.outside != null) ('Outdoors', event.outside! ? 'Yes' : 'No'),
    ];

    return SectionCard(
      child: Column(
        children: [
          for (int i = 0; i < rows.length; i++) ...[
            if (i > 0) const SectionDivider(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      rows[i].$1,
                      style:
                          TextStyle(fontSize: 15, color: context.secondaryText),
                    ),
                  ),
                  Text(rows[i].$2, style: const TextStyle(fontSize: 15)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
