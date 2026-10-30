import 'package:flutter/cupertino.dart';
import 'package:go_router/go_router.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';
import 'package:tts_bandmate/features/events/data/models/event_detail.dart';
import 'package:tts_bandmate/features/events/widgets/event_sections/section_primitives.dart';
import 'package:url_launcher/url_launcher.dart';

// ── Live setlist button ───────────────────────────────────────────────────────

class LiveSetlistButton extends StatelessWidget {
  const LiveSetlistButton({super.key, required this.eventKey});
  final String eventKey;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: CupertinoButton.filled(
        onPressed: () => context.push('/events/$eventKey/setlist/live'),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(CupertinoIcons.music_note, size: 18),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                'Join Live Setlist',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Performance ───────────────────────────────────────────────────────────────

class PerformanceSection extends StatelessWidget {
  const PerformanceSection({super.key, required this.performance});
  final Performance performance;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (performance.notes != null && performance.notes!.isNotEmpty) ...[
          SectionCard(child: PerformanceNotes(notes: performance.notes!)),
          const SizedBox(height: 8),
        ],
        if (performance.songs.isNotEmpty) ...[
          Text('Songs',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: context.secondaryText)),
          const SizedBox(height: 6),
          SectionCard(
            child: Column(
              children: [
                for (int i = 0; i < performance.songs.length; i++) ...[
                  if (i > 0)
                    Container(
                        height: 0.5,
                        color: CupertinoColors.separator.resolveFrom(context)),
                  SongRow(index: i + 1, song: performance.songs[i]),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (performance.charts.isNotEmpty) ...[
          Text('Sheet music',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: context.secondaryText)),
          const SizedBox(height: 6),
          SectionCard(
            child: Column(
              children: [
                for (int i = 0; i < performance.charts.length; i++) ...[
                  if (i > 0)
                    Container(
                        height: 0.5,
                        color: CupertinoColors.separator.resolveFrom(context)),
                  ChartRow(chart: performance.charts[i]),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class SongRow extends StatelessWidget {
  const SongRow({super.key, required this.index, required this.song});
  final int index;
  final PerformanceSong song;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '$index.',
              style: TextStyle(fontSize: 13, color: context.secondaryText),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (song.title != null && song.title!.isNotEmpty)
                  Text(song.title!, style: const TextStyle(fontSize: 15)),
                if (song.url != null && song.url!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  GestureDetector(
                    onTap: () => _launch(song.url!),
                    child: Text(
                      song.url!,
                      style: TextStyle(
                          fontSize: 13,
                          color:
                              CupertinoColors.activeBlue.resolveFrom(context)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _launch(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class ChartRow extends StatelessWidget {
  const ChartRow({super.key, required this.chart});
  final PerformanceChart chart;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(CupertinoIcons.doc_text, size: 16, color: context.secondaryText),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(chart.title, style: const TextStyle(fontSize: 15)),
                if (chart.composer != null && chart.composer!.isNotEmpty)
                  Text(chart.composer!,
                      style: TextStyle(
                          fontSize: 13, color: context.secondaryText)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Performance notes (rule chip + remaining text) ───────────────────────────

/// Renders the first line of the performance notes as a rule chip when it's
/// short (e.g. "Only upbeat songs"), followed by the rest as plain text. The
/// notes remain plain text on the server; this is display-only.
class PerformanceNotes extends StatelessWidget {
  const PerformanceNotes({super.key, required this.notes});
  final String notes;

  static const _maxChipLength = 60;

  @override
  Widget build(BuildContext context) {
    final lines = notes
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return const SizedBox.shrink();
    final first = lines.first;
    final asChip = first.length <= _maxChipLength;
    final rest = (asChip ? lines.skip(1) : lines).join('\n');
    final tint = CupertinoColors.systemOrange.resolveFrom(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (asChip)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(first,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: tint)),
          ),
        if (asChip && rest.isNotEmpty) const SizedBox(height: 8),
        if (rest.isNotEmpty) Text(rest, style: const TextStyle(fontSize: 15)),
      ],
    );
  }
}
