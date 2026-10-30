import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';

import '../data/event_music.dart';
import '../data/models/event_detail.dart';
import '../providers/event_music_provider.dart';
import '../providers/events_provider.dart';
import '../widgets/add_to_rehearsal.dart';
import '../widgets/event_sections/client_requests_card.dart';
import '../widgets/event_sections/performance_section.dart';
import '../widgets/event_sections/section_primitives.dart';
import '../widgets/event_tabs/music_tab.dart' show songLabel;
import '../widgets/song_sheet.dart';

enum _Section {
  toLearn('To learn'),
  dances('Dances'),
  requests('Requests'),
  setlist('Setlist'),
  charts('Charts');

  const _Section(this.label);
  final String label;
}

/// Music page (A12): everything the band needs to get ready for this gig's
/// music — songs to learn, special dances, client requests, the setlist and
/// charts & recordings.
class EventMusicScreen extends ConsumerStatefulWidget {
  const EventMusicScreen({super.key, required this.eventKey});
  final String eventKey;

  @override
  ConsumerState<EventMusicScreen> createState() => _EventMusicScreenState();
}

class _EventMusicScreenState extends ConsumerState<EventMusicScreen> {
  final _keys = {for (final s in _Section.values) s: GlobalKey()};

  void _jump(_Section s) {
    final ctx = _keys[s]!.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  Future<void> _openEditor() async {
    await context.push('/events/${widget.eventKey}/setlist');
    // The editor may have changed the setlist.
    ref.invalidate(eventMusicProvider(widget.eventKey));
  }

  @override
  Widget build(BuildContext context) {
    final eventAsync = ref.watch(eventDetailProvider(widget.eventKey));
    final event = eventAsync.value;
    final musicAsync = ref.watch(eventMusicProvider(widget.eventKey));

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Music'),
            if (event != null)
              Text(
                '${event.title} · ${DateFormat('MMM d').format(event.parsedDate)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: context.secondaryText,
                ),
              ),
          ],
        ),
      ),
      child: SafeArea(
        child: event == null || musicAsync.isLoading && !musicAsync.hasValue
            ? const Center(child: CupertinoActivityIndicator())
            : _body(context, event, musicAsync.value),
      ),
    );
  }

  Widget _body(BuildContext context, EventDetail event, EventMusic? music) {
    final toLearn = music?.toLearn ?? const [];
    final dances = (event.wedding?.dances ?? const <WeddingDance>[])
        .where((d) => !isPlaceholderSong(d.data))
        .toList();
    final requests = music?.requestsSummary;
    final setlist = music?.setlist;
    final perf = event.performance;
    final hasCharts = perf != null &&
        (perf.charts.isNotEmpty ||
            perf.songs.any((s) => s.url?.isNotEmpty ?? false));
    final catalog = music?.bandSongs ?? const [];

    final sections = <_Section, Widget>{
      if (toLearn.isNotEmpty)
        _Section.toLearn: _Block(
          title: 'To learn',
          caption: 'Not in our catalog',
          child: _Rows(children: [
            for (final e in toLearn)
              _TapRow(
                title: e.displayTitle,
                subtitle: songLabel('Not in catalog', e.displayArtist),
                onTap: () => showSongSheet(context,
                    event: event,
                    song: SongSheetSong.fromEntry(e,
                        role: 'Not in our catalog', event: event)),
              ),
          ]),
        ),
      if (dances.isNotEmpty)
        _Section.dances: _Block(
          title: 'Special dances',
          child: _Rows(children: [
            for (final d in dances)
              _TapRow(
                title: d.data!.trim(),
                subtitle: danceLabel(d.title),
                onTap: () => showSongSheet(context,
                    event: event,
                    song: SongSheetSong.fromDance(d,
                        event: event, catalog: catalog)),
              ),
          ]),
        ),
      if (requests != null)
        _Section.requests: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClientRequestsCard(eventKey: event.key, summary: requests),
            if (requests.mustPlay.isNotEmpty && setlist != null) ...[
              const SizedBox(height: 6),
              Text(
                '${mustPlaysOnSetlist(music!.requests, setlist)} of the '
                '${requests.mustPlay.length} must-plays are on the setlist.',
                style: TextStyle(fontSize: 13, color: context.secondaryText),
              ),
            ],
          ],
        ),
      _Section.setlist: _SetlistBlock(
        music: music,
        onOpenEditor: _openEditor,
      ),
      if (hasCharts)
        _Section.charts: _Block(
          title: 'Charts & recordings',
          child: _Rows(children: [
            for (final c in perf.charts) ChartRow(chart: c),
            for (int i = 0; i < perf.songs.length; i++)
              if (perf.songs[i].url?.isNotEmpty ?? false)
                SongRow(index: i + 1, song: perf.songs[i]),
          ]),
        ),
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Jump chips only help with more than one section.
          if (sections.length > 1) ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final s in sections.keys)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _Chip(
                        label: s == _Section.toLearn
                            ? 'To learn ${toLearn.length}'
                            : s.label,
                        highlight: s == _Section.toLearn,
                        onTap: () => _jump(s),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          AddToRehearsalAction(
            event: event,
            titles: [for (final e in toLearn) e.displayTitle],
          ),
          for (final entry in sections.entries) ...[
            const SizedBox(height: 20),
            KeyedSubtree(key: _keys[entry.key], child: entry.value),
          ],
        ],
      ),
    );
  }
}

class _SetlistBlock extends StatelessWidget {
  const _SetlistBlock({required this.music, required this.onOpenEditor});
  final EventMusic? music;
  final VoidCallback onOpenEditor;

  @override
  Widget build(BuildContext context) {
    final setlist = music?.setlist;
    final sets = setlist == null ? const <SetlistSet>[] : splitSets(setlist);
    final secondary = TextStyle(fontSize: 13, color: context.secondaryText);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: SectionHeader(title: 'Setlist')),
            if (setlist != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: (setlist.isReady
                          ? CupertinoColors.systemGreen
                          : CupertinoColors.systemGrey)
                      .resolveFrom(context)
                      .withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  setlist.isReady ? 'Ready' : 'Draft',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: (setlist.isReady
                            ? CupertinoColors.systemGreen
                            : CupertinoColors.systemGrey)
                        .resolveFrom(context),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text('${setlist.songCount} songs', style: secondary),
            ],
          ],
        ),
        const SizedBox(height: 8),
        _Rows(children: [
          if (setlist == null || sets.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text('No setlist yet',
                  style: TextStyle(fontSize: 15, color: context.secondaryText)),
            ),
          for (final s in sets)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 52,
                    child: Text(
                      sets.length == 1 ? 'Songs' : 'Set ${s.number}',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      s.songs.take(3).map((e) => e.displayTitle).join(', ') +
                          (s.songs.length > 3 ? '…' : ''),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: secondary.copyWith(fontSize: 15),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('${s.songs.length}', style: secondary),
                ],
              ),
            ),
          _TapRow(
            title: 'Open setlist editor',
            onTap: onOpenEditor,
            link: true,
          ),
        ]),
      ],
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.title, required this.child, this.caption});
  final String title;
  final String? caption;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: SectionHeader(title: title)),
            if (caption != null)
              Text(caption!,
                  style: TextStyle(fontSize: 13, color: context.secondaryText)),
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _Rows extends StatelessWidget {
  const _Rows({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final sep = CupertinoColors.separator.resolveFrom(context);
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < children.length; i++) ...[
            if (i > 0) Container(height: 0.5, color: sep),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _TapRow extends StatelessWidget {
  const _TapRow({
    required this.title,
    required this.onTap,
    this.subtitle,
    this.link = false,
  });
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool link;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: subtitle == null ? title : '$title. $subtitle',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: link ? FontWeight.w600 : null,
                          color: link
                              ? CupertinoColors.activeBlue.resolveFrom(context)
                              : context.primaryText,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(subtitle!,
                            style: TextStyle(
                                fontSize: 13, color: context.secondaryText)),
                      ],
                    ],
                  ),
                ),
                Icon(CupertinoIcons.chevron_right,
                    size: 14, color: context.tertiaryText),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(
      {required this.label, required this.onTap, this.highlight = false});
  final String label;
  final VoidCallback onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final orange = CupertinoColors.systemOrange.resolveFrom(context);
    return Semantics(
      button: true,
      label: 'Jump to $label',
      excludeSemantics: true,
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        minimumSize: const Size(44, 36),
        color: highlight
            ? orange.withValues(alpha: 0.16)
            : CupertinoColors.secondarySystemGroupedBackground
                .resolveFrom(context),
        borderRadius: BorderRadius.circular(18),
        onPressed: onTap,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: highlight ? orange : context.primaryText,
          ),
        ),
      ),
    );
  }
}
