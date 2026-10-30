import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';

import '../../data/event_music.dart';
import '../../data/models/event_detail.dart';
import '../../providers/event_music_provider.dart';
import '../event_sections/performance_section.dart';
import '../event_sections/section_primitives.dart';

/// Music tab (A3): performance notes, a summary of the gig's music that opens
/// the Music page, and Run the live setlist.
class MusicTab extends ConsumerWidget {
  const MusicTab({super.key, required this.event, required this.onRunLive});
  final EventDetail event;

  /// Opens the live setlist (with the not-gig-day confirm).
  final VoidCallback onRunLive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = event.performance?.notes;
    final music = ref.watch(eventMusicProvider(event.key)).value;
    final canRun = event.liveSessionId != null || event.canWrite;

    final blocks = <Widget>[
      if (notes != null && notes.isNotEmpty)
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(title: 'Performance notes'),
            const SizedBox(height: 8),
            SectionCard(child: PerformanceNotes(notes: notes)),
          ],
        ),
      MusicSummaryCard(event: event, music: music),
      if (canRun)
        SizedBox(
          width: double.infinity,
          child: CupertinoButton.filled(
            onPressed: onRunLive,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(CupertinoIcons.music_note, size: 18),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    event.liveSessionId != null
                        ? 'Join the live setlist'
                        : 'Run the live setlist',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
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

/// Songs / to learn / requests counts and the first songs to learn. Opens
/// the Music page.
class MusicSummaryCard extends StatelessWidget {
  const MusicSummaryCard({super.key, required this.event, required this.music});
  final EventDetail event;
  final EventMusic? music;

  @override
  Widget build(BuildContext context) {
    final songs = music?.songCount ?? event.performance?.songs.length ?? 0;
    final toLearn = music?.toLearn ?? const [];
    final requests = music?.requestsSummary?.mustPlay.length ?? 0;
    final sep = CupertinoColors.separator.resolveFrom(context);

    return Semantics(
      button: true,
      label: 'Open music. $songs songs, ${toLearn.length} to learn, '
          '$requests requests',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => context.push('/events/${event.key}/music'),
        child: SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(child: _Stat(value: songs, label: 'songs')),
                    Expanded(
                      child: _Stat(
                        value: toLearn.length,
                        label: 'to learn',
                        highlight: toLearn.isNotEmpty,
                      ),
                    ),
                    Expanded(child: _Stat(value: requests, label: 'requests')),
                  ],
                ),
              ),
              if (toLearn.isNotEmpty) ...[
                Container(
                    height: 0.5,
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    color: sep),
                Text(
                  'Not in our catalog',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.secondaryText,
                  ),
                ),
                const SizedBox(height: 4),
                for (final e in toLearn.take(2))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      songLabel(e.displayTitle, e.displayArtist),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15),
                    ),
                  ),
                if (toLearn.length > 2)
                  Text(
                    '+ ${toLearn.length - 2} more',
                    style:
                        TextStyle(fontSize: 13, color: context.secondaryText),
                  ),
              ],
              Container(
                  height: 0.5,
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  color: sep),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Open music',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: CupertinoColors.activeBlue.resolveFrom(context),
                      ),
                    ),
                  ),
                  Icon(CupertinoIcons.chevron_right,
                      size: 14, color: context.tertiaryText),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Title · Artist", or the title alone.
String songLabel(String title, String? artist) =>
    (artist?.isNotEmpty ?? false) ? '$title · $artist' : title;

class _Stat extends StatelessWidget {
  const _Stat(
      {required this.value, required this.label, this.highlight = false});
  final int value;
  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          '$value',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: highlight
                ? CupertinoColors.systemOrange.resolveFrom(context)
                : context.primaryText,
          ),
        ),
        Text(label,
            style: TextStyle(fontSize: 13, color: context.secondaryText)),
      ],
    );
  }
}
