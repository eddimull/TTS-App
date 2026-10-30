import 'package:flutter/cupertino.dart';
import 'package:go_router/go_router.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';

import '../../data/models/event_detail.dart';
import '../event_glance_card.dart';
import '../event_sections/contact_row.dart';
import '../event_sections/event_details_card.dart';
import '../event_sections/lodging_section.dart';
import '../event_sections/roster_summary_row.dart';
import '../event_sections/section_primitives.dart';
import '../event_sections/wedding_section.dart';

/// Overview tab: at-a-glance card, the wedding card (or "Event details" for
/// other event types), people and lodging.
class OverviewTab extends StatelessWidget {
  const OverviewTab({
    super.key,
    required this.event,
    required this.onOpenRoster,
    this.onShowTimeTap,
  });

  final EventDetail event;
  final VoidCallback onOpenRoster;

  /// Jumps to the Timeline tab (the glance card's show-time row).
  final VoidCallback? onShowTimeTap;

  @override
  Widget build(BuildContext context) {
    final wedding = event.wedding;
    final showWedding = wedding != null &&
        (wedding.onsite != null ||
            wedding.colors != null ||
            wedding.dances.isNotEmpty);
    final showDetails = !showWedding && EventDetailsCard.hasContent(event);
    final hasGlance = EventGlanceCard.hasContent(event);
    final hasPeople = event.contacts.isNotEmpty || event.members.isNotEmpty;
    final hasLodging = event.lodgings.isNotEmpty;

    if (!showWedding &&
        !showDetails &&
        !hasGlance &&
        !hasPeople &&
        !hasLodging) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text(
            'No details yet',
            style: TextStyle(fontSize: 15, color: context.secondaryText),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasGlance)
          EventGlanceCard(
            event: event,
            onShowTimeTap: onShowTimeTap,
            onLodgingTap: (lodgingId) => context.push('/lodging/$lodgingId'),
          ),
        if (showWedding) ...[
          SizedBox(height: hasGlance ? 20 : 0),
          const SectionHeader(title: 'Wedding'),
          const SizedBox(height: 8),
          WeddingSection(wedding: wedding),
        ],
        if (showDetails) ...[
          SizedBox(height: hasGlance ? 20 : 0),
          const SectionHeader(title: 'Event details'),
          const SizedBox(height: 8),
          EventDetailsCard(event: event),
        ],
        if (hasPeople) ...[
          SizedBox(height: (hasGlance || showWedding || showDetails) ? 20 : 0),
          const SectionHeader(title: 'People'),
          const SizedBox(height: 8),
          ...event.contacts.map((c) => ContactRow(contact: c)),
          if (event.members.isNotEmpty)
            RosterSummaryRow(event: event, onTap: onOpenRoster),
        ],
        if (hasLodging) ...[
          SizedBox(
            height:
                (hasGlance || showWedding || showDetails || hasPeople) ? 20 : 0,
          ),
          const SectionHeader(title: 'Lodging'),
          const SizedBox(height: 8),
          LodgingLinksSection(lodgings: event.lodgings),
        ],
      ],
    );
  }
}
