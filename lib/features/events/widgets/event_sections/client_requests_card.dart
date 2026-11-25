import 'package:flutter/cupertino.dart';
import 'package:go_router/go_router.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';

import '../../data/client_requests_summary.dart';
import 'section_primitives.dart';

/// The client's song requests from a submitted questionnaire: song-picker
/// picks and songs written into its free-text answers. Each list shows its first few songs with a "Show all"
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
  final _expanded = <String>{};

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
              for (final (i, list) in [
                ('Must play', s.mustPlay),
                ('If time', s.ifTime),
                ('Do not play', s.doNotPlay),
                ('Client wishes', s.guidelines),
              ].where((l) => l.$2.isNotEmpty).indexed) ...[
                if (i > 0) const SectionDivider(),
                _PickList(
                  label: list.$1,
                  songs: list.$2,
                  notInCatalog: s.notInCatalog,
                  expanded: _expanded.contains(list.$1),
                  onShowAll: () => setState(() => _expanded.add(list.$1)),
                ),
              ],
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
    this.notInCatalog = const {},
    required this.expanded,
    required this.onShowAll,
  });

  final String label;
  final List<String> songs;

  /// Entries to mark "Not in catalog".
  final Set<String> notInCatalog;
  final bool expanded;
  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context) {
    final shown =
        expanded ? songs : songs.take(ClientRequestsCard.previewCount).toList();
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
              child: Text.rich(TextSpan(
                text: song,
                style: const TextStyle(fontSize: 15),
                children: [
                  if (notInCatalog.contains(song))
                    TextSpan(
                      text: '  Not in catalog',
                      style: TextStyle(
                          fontSize: 13,
                          color: CupertinoColors.systemOrange
                              .resolveFrom(context)),
                    ),
                ],
              )),
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
