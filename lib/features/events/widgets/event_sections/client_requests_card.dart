import 'package:flutter/cupertino.dart';
import 'package:go_router/go_router.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';

import '../../data/client_requests_summary.dart';
import 'section_primitives.dart';

/// The client's must-play / do-not-play picks from a submitted
/// questionnaire. Each list shows its first few songs with a "Show all"
/// toggle; the last row opens the setlist editor's Catalog view.
class ClientRequestsCard extends StatefulWidget {
  const ClientRequestsCard({
    super.key,
    required this.eventKey,
    required this.summary,
  });

  final String eventKey;
  final ClientRequestsSummary summary;

  static const int previewCount = 5;

  @override
  State<ClientRequestsCard> createState() => _ClientRequestsCardState();
}

class _ClientRequestsCardState extends State<ClientRequestsCard> {
  bool _mustExpanded = false;
  bool _doNotExpanded = false;

  void _openCatalog() =>
      context.push('/events/${widget.eventKey}/setlist?view=catalog');

  @override
  Widget build(BuildContext context) {
    final s = widget.summary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Client requests'),
        if (s.sourceName != null) ...[
          const SizedBox(height: 2),
          Text(
            'From ${s.sourceName}',
            style: TextStyle(fontSize: 13, color: context.secondaryText),
          ),
        ],
        const SizedBox(height: 8),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (s.mustPlay.isNotEmpty)
                _PickList(
                  label: 'Must play',
                  songs: s.mustPlay,
                  expanded: _mustExpanded,
                  onShowAll: () => setState(() => _mustExpanded = true),
                ),
              if (s.mustPlay.isNotEmpty && s.doNotPlay.isNotEmpty)
                const SectionDivider(),
              if (s.doNotPlay.isNotEmpty)
                _PickList(
                  label: 'Do not play',
                  songs: s.doNotPlay,
                  expanded: _doNotExpanded,
                  onShowAll: () => setState(() => _doNotExpanded = true),
                ),
              const SectionDivider(),
              Semantics(
                button: true,
                label: 'Open the client requests in the setlist',
                excludeSemantics: true,
                onTap: _openCatalog,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _openCatalog,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text('Open in setlist',
                              style: TextStyle(fontSize: 15)),
                        ),
                        Icon(CupertinoIcons.chevron_right,
                            size: 16, color: context.tertiaryText),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PickList extends StatelessWidget {
  const _PickList({
    required this.label,
    required this.songs,
    required this.expanded,
    required this.onShowAll,
  });

  final String label;
  final List<String> songs;
  final bool expanded;
  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context) {
    final shown = expanded
        ? songs
        : songs.take(ClientRequestsCard.previewCount).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label (${songs.length})',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.secondaryText),
          ),
          const SizedBox(height: 4),
          for (final song in shown)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(song, style: const TextStyle(fontSize: 15)),
            ),
          if (shown.length < songs.length)
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(44, 44),
              onPressed: onShowAll,
              child: Text('Show all (${songs.length})'),
            ),
        ],
      ),
    );
  }
}
