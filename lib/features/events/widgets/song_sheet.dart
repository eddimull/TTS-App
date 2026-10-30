import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/providers/selected_band_provider.dart';
import '../../library/data/models/chart.dart';
import '../../library/providers/library_provider.dart';
import '../../setlist_editor/data/models/event_setlist.dart';
import '../data/event_music.dart';
import '../data/models/event_detail.dart';
import 'add_to_rehearsal.dart';

/// What the song sheet shows about one song.
class SongSheetSong {
  const SongSheetSong({
    required this.title,
    this.artist,
    this.role,
    this.songId,
    this.songKey,
    this.bpm,
    this.lead,
    this.notes,
    this.recordingUrl,
  });

  final String title;
  final String? artist;

  /// Why it's on this gig, e.g. "First dance" or "Not in our catalog".
  final String? role;
  final int? songId;
  final String? songKey;
  final int? bpm;
  final String? lead;
  final String? notes;
  final String? recordingUrl;

  /// From a setlist entry, with catalog details when it is a catalog song.
  factory SongSheetSong.fromEntry(
    SetlistEntry e, {
    required String? role,
    required EventDetail event,
  }) =>
      SongSheetSong(
        title: e.displayTitle,
        artist: e.displayArtist,
        role: role,
        songId: e.songId,
        songKey: e.songKey,
        bpm: e.bpm,
        lead: e.leadSinger,
        notes: e.notes,
        recordingUrl: recordingFor(e.displayTitle, event),
      );

  /// From a special dance; its song is matched to the catalog by title.
  factory SongSheetSong.fromDance(
    WeddingDance d, {
    required EventDetail event,
    required List<BandSongSummary> catalog,
  }) {
    final title = (d.data ?? '').trim();
    final song = findCatalogSong(title, catalog);
    return SongSheetSong(
      title: title,
      artist: song?.artist,
      role: danceLabel(d.title),
      songId: song?.id,
      songKey: song?.songKey,
      bpm: song?.bpm,
      lead: song?.leadSinger,
      recordingUrl: recordingFor(title, event),
    );
  }
}

/// The event's reference recording for [title], if it has one.
String? recordingFor(String title, EventDetail event) {
  for (final s in event.performance?.songs ?? const <PerformanceSong>[]) {
    final url = s.url;
    if (url == null || url.isEmpty) continue;
    if (sameSongTitle(s.title ?? '', title)) return url;
  }
  return null;
}

/// The band's library chart for a song: linked to it, or with its title.
Chart? chartFor(SongSheetSong song, List<Chart> charts, int? bandId) {
  final mine = charts.where((c) => bandId == null || c.bandId == bandId);
  if (song.songId != null) {
    for (final c in mine) {
      if (c.song?.id == song.songId) return c;
    }
  }
  for (final c in mine) {
    if (sameSongTitle(c.title, song.title)) return c;
  }
  return null;
}

Future<void> showSongSheet(
  BuildContext context, {
  required EventDetail event,
  required SongSheetSong song,
}) =>
    showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => SongSheet(event: event, song: song),
    );

/// Song sheet (A13): what you need to learn one song for this gig.
class SongSheet extends ConsumerWidget {
  const SongSheet({super.key, required this.event, required this.song});
  final EventDetail event;
  final SongSheetSong song;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bandId = ref.watch(selectedBandProvider).value;
    final charts = ref.watch(libraryProvider).value?.charts ?? const <Chart>[];
    final chart = chartFor(song, charts, bandId);
    final sub = [
      if (song.artist?.isNotEmpty ?? false) song.artist!,
      if (song.role?.isNotEmpty ?? false) song.role!,
    ].join(' · ');
    final hasTiles =
        song.songKey != null || song.bpm != null || song.lead != null;
    final hasLearn = chart != null ||
        song.recordingUrl != null ||
        (song.notes?.isNotEmpty ?? false);

    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9),
      decoration: BoxDecoration(
        color: CupertinoColors.systemGroupedBackground.resolveFrom(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 5,
              decoration: BoxDecoration(
                color: CupertinoColors.systemGrey3.resolveFrom(context),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  const SizedBox(width: 60),
                  const Expanded(
                    child: Text(
                      'Song',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                    ),
                  ),
                  SizedBox(
                    width: 60,
                    child: CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Done',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        song.title,
                        style: const TextStyle(
                            fontSize: 24, fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (sub.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(sub,
                          style: TextStyle(
                              fontSize: 15, color: context.secondaryText)),
                    ],
                    if (hasTiles) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                              child: _Tile(label: 'Key', value: song.songKey)),
                          const SizedBox(width: 8),
                          Expanded(
                              child: _Tile(
                                  label: 'BPM', value: song.bpm?.toString())),
                          const SizedBox(width: 8),
                          Expanded(
                              child: _Tile(label: 'Lead', value: song.lead)),
                        ],
                      ),
                    ],
                    const SizedBox(height: 20),
                    const _Label('Learn it'),
                    const SizedBox(height: 6),
                    _Group(children: [
                      if (chart != null)
                        _LinkRow(
                          title: 'Chart · ${chart.title}',
                          subtitle: 'From the library',
                          onTap: () {
                            Navigator.pop(context);
                            context.push('/library/${chart.id}',
                                extra: chart.bandId);
                          },
                        ),
                      if (song.recordingUrl != null)
                        _LinkRow(
                          title: 'Reference recording',
                          subtitle: song.recordingUrl!,
                          onTap: () {
                            final uri = Uri.tryParse(song.recordingUrl!);
                            if (uri != null) {
                              launchUrl(uri,
                                  mode: LaunchMode.externalApplication);
                            }
                          },
                        ),
                      if (song.notes?.isNotEmpty ?? false)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Notes',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: context.secondaryText)),
                              const SizedBox(height: 2),
                              Text(song.notes!,
                                  style: const TextStyle(fontSize: 15)),
                            ],
                          ),
                        ),
                      if (!hasLearn)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          child: Text(
                            'No chart or recording yet',
                            style: TextStyle(
                                fontSize: 15, color: context.secondaryText),
                          ),
                        ),
                    ]),
                    const SizedBox(height: 20),
                    AddToRehearsalAction(
                      event: event,
                      titles: [song.title],
                      single: true,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 16),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
            color: context.secondaryText,
          ),
        ),
      );
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value});
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label ${value ?? 'not set'}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: CupertinoColors.secondarySystemGroupedBackground
              .resolveFrom(context),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(fontSize: 12, color: context.secondaryText)),
            Text(
              value ?? '—',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color:
                    value == null ? context.tertiaryText : context.primaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final sep = CupertinoColors.separator.resolveFrom(context);
    return Container(
      decoration: BoxDecoration(
        color: CupertinoColors.secondarySystemGroupedBackground
            .resolveFrom(context),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < children.length; i++) ...[
            if (i > 0)
              Container(
                  height: 0.5,
                  margin: const EdgeInsets.only(left: 16),
                  color: sep),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow(
      {required this.title, required this.subtitle, required this.onTap});
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$title. $subtitle',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13, color: context.secondaryText)),
                  ],
                ),
              ),
              Icon(CupertinoIcons.chevron_right,
                  size: 14, color: context.tertiaryText),
            ],
          ),
        ),
      ),
    );
  }
}
