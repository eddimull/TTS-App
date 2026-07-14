import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';
import 'package:tts_bandmate/shared/widgets/empty_state_view.dart';
import 'package:tts_bandmate/shared/widgets/error_view.dart';

import '../data/models/song.dart';
import '../providers/songs_provider.dart';

/// Read-only song detail. Renders from [songsProvider] list state (there is
/// no per-song GET endpoint), so edits saved by the form show immediately.
class SongDetailScreen extends ConsumerWidget {
  const SongDetailScreen({super.key, required this.songId});

  final int songId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songsAsync = ref.watch(songsProvider);

    return songsAsync.when(
      loading: () => const CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(middle: Text('Song')),
        child: Center(child: CupertinoActivityIndicator()),
      ),
      error: (e, _) => CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(middle: Text('Song')),
        child: ErrorView(
          message: ErrorView.friendlyMessage(e),
          onRetry: () => ref.read(songsProvider.notifier).refresh(),
        ),
      ),
      data: (state) {
        final song = state.songs.where((s) => s.id == songId).firstOrNull;
        if (song == null) {
          return const CupertinoPageScaffold(
            navigationBar: CupertinoNavigationBar(middle: Text('Song')),
            child: EmptyStateView(
              icon: CupertinoIcons.music_mic,
              title: 'Song not found',
              subtitle: 'It may have been deleted on another device.',
            ),
          );
        }
        return _SongDetailBody(song: song);
      },
    );
  }
}

class _SongDetailBody extends StatelessWidget {
  const _SongDetailBody({required this.song});

  final Song song;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(song.title),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => context.push('/songs/${song.id}/edit', extra: song),
          child: const Text('Edit'),
        ),
      ),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth =
                constraints.maxWidth > 700 ? 700.0 : constraints.maxWidth;
            return Center(
              child: SizedBox(
                width: maxWidth,
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  children: [
                    const _SectionHeader(label: 'Details'),
                    _DetailCard(song: song),
                    if (song.notes.isNotEmpty) ...[
                      const _SectionHeader(label: 'Notes'),
                      _NotesCard(notes: song.notes),
                    ],
                    const _SectionHeader(label: 'Sheet music'),
                    if (song.charts.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Text(
                          'No sheet music linked to this song yet.',
                          style: TextStyle(
                            fontSize: 14,
                            color: context.secondaryText,
                          ),
                        ),
                      )
                    else
                      ...song.charts.map(
                        (chart) => _ChartRow(
                          chart: chart,
                          onTap: () => context.push(
                            '/library/${chart.id}',
                            extra: song.bandId,
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: context.secondaryText,
        ),
      ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.song});

  final Song song;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[
      if (song.artist.isNotEmpty) _MetaRow(label: 'Artist', value: song.artist),
      if (song.songKey.isNotEmpty) _MetaRow(label: 'Key', value: song.songKey),
      if (song.genre.isNotEmpty) _MetaRow(label: 'Genre', value: song.genre),
      if (song.bpm > 0) _MetaRow(label: 'BPM', value: song.bpm.toString()),
      if (song.rating != null)
        _MetaRow(label: 'Rating', value: '${song.rating} / 10'),
      if (song.energy != null)
        _MetaRow(label: 'Energy', value: '${song.energy} / 10'),
      if (song.leadSinger != null)
        _MetaRow(label: 'Lead singer', value: song.leadSinger!.displayName),
      if (song.transitionSong != null)
        _MetaRow(label: 'Transition', value: song.transitionSong!.title),
      _MetaRow(label: 'Status', value: song.active ? 'Active' : 'Inactive'),
    ];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            rows[i],
            if (i < rows.length - 1)
              Container(
                height: 0.5,
                margin: const EdgeInsets.only(left: 16),
                color: CupertinoColors.separator.resolveFrom(context),
              ),
          ],
        ],
      ),
    );
  }
}

class _NotesCard extends StatelessWidget {
  const _NotesCard({required this.notes});

  final String notes;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(notes, style: const TextStyle(fontSize: 14)),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(fontSize: 14, color: context.secondaryText),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );
  }
}

class _ChartRow extends StatelessWidget {
  const _ChartRow({required this.chart, required this.onTap});

  final SongChartSummary chart;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${chart.title}. Opens the sheet music detail.',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color:
                CupertinoColors.tertiarySystemBackground.resolveFrom(context),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                CupertinoIcons.doc_text,
                size: 18,
                color: context.secondaryText,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  chart.title,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                CupertinoIcons.chevron_right,
                size: 14,
                color: context.tertiaryText,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
