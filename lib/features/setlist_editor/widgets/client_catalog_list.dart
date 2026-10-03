import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import '../data/models/event_setlist.dart';
import 'client_request_marker.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';

/// The band's whole active catalog, alphabetical, with the client's must-play
/// songs starred and do-not-play songs struck out. Shown as the "Catalog"
/// segment of the setlist editor when a submitted questionnaire carries picks.
class ClientCatalogList extends StatelessWidget {
  const ClientCatalogList({
    super.key,
    required this.songs,
    required this.requests,
  });

  final List<BandSongSummary> songs;
  final ClientSongRequests requests;

  @override
  Widget build(BuildContext context) {
    final sorted = [...songs]
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

    return ListView.builder(
      itemCount: sorted.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) return _SummaryHeader(songs: songs, requests: requests);
        final song = sorted[i - 1];
        return _CatalogRow(song: song, status: requests.statusFor(song.id));
      },
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({required this.songs, required this.requests});

  final List<BandSongSummary> songs;
  final ClientSongRequests requests;

  @override
  Widget build(BuildContext context) {
    // Count only picks that resolve to a catalog song actually listed.
    final ids = songs.map((s) => s.id).toSet();
    final must = requests.mustPlayIds.where(ids.contains).length;
    final skip = requests.doNotPlayIds.where(ids.contains).length;

    final counts = <String>[
      if (must > 0) '$must must play',
      if (skip > 0) '$skip do not play',
    ].join(', ');

    final source = <String>[
      if ((requests.sourceName ?? '').isNotEmpty) 'from ${requests.sourceName}',
      if (requests.submittedAt != null)
        'submitted ${DateFormat('MMM d').format(requests.submittedAt!.toLocal())}',
    ].join(', ');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: CupertinoColors.systemGrey6.resolveFrom(context),
        border: Border(
          bottom: BorderSide(
            color: CupertinoColors.separator.resolveFrom(context),
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Client requests',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: context.secondaryText,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            source.isEmpty ? counts : '$counts, $source',
            style: TextStyle(fontSize: 14, color: context.primaryText),
          ),
        ],
      ),
    );
  }
}

class _CatalogRow extends StatelessWidget {
  const _CatalogRow({required this.song, required this.status});

  final BandSongSummary song;
  final ClientSongStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: CupertinoColors.separator.resolveFrom(context),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Fixed-width marker column keeps titles aligned across rows.
          SizedBox(
            width: 24,
            child: status == ClientSongStatus.mustPlay
                ? const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: ClientRequestStar(),
                  )
                : null,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  song.title,
                  style: clientRequestTextStyle(
                    context,
                    status,
                    TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: context.primaryText,
                    ),
                  ),
                ),
                if ((song.artist ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      song.artist!,
                      style: clientRequestTextStyle(
                        context,
                        status,
                        TextStyle(fontSize: 13, color: context.secondaryText),
                      ),
                    ),
                  ),
                if (status != ClientSongStatus.none)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: ClientRequestCaption(status),
                  ),
              ],
            ),
          ),
          if (song.songKey != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                song.songKey!,
                style: TextStyle(fontSize: 13, color: context.secondaryText),
              ),
            ),
        ],
      ),
    );
  }
}
