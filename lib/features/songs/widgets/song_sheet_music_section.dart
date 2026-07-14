import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/auth/providers/auth_provider.dart';
import 'package:tts_bandmate/features/library/data/models/chart.dart';
import 'package:tts_bandmate/features/library/providers/library_provider.dart';
import 'package:tts_bandmate/features/library/screens/create_chart_screen.dart';
import 'package:tts_bandmate/shared/widgets/error_view.dart';

import '../data/models/song.dart';

/// The "Sheet music" section of the song detail screen: lists the charts
/// linked to [song], and lets the user add/move/unlink them.
///
/// Mirrors the previous inline section + `_ChartRow` from
/// `song_detail_screen.dart`, plus link-management actions backed by
/// [libraryProvider] / `LibraryNotifier.updateChartSong`.
class SongSheetMusicSection extends ConsumerStatefulWidget {
  const SongSheetMusicSection({super.key, required this.song});

  final Song song;

  @override
  ConsumerState<SongSheetMusicSection> createState() =>
      _SongSheetMusicSectionState();
}

class _SongSheetMusicSectionState
    extends ConsumerState<SongSheetMusicSection> {
  bool _busy = false;

  Song get song => widget.song;

  /// PATCHes the chart-song link. Does NOT own [_busy] — the calling flow
  /// (`_showAddPicker` / `_showChartOptions`) holds the guard for its whole
  /// duration and clears it in its own `finally`.
  Future<void> _patch(int chartId, int? songId) async {
    if (!mounted) return;
    try {
      await ref
          .read(libraryProvider.notifier)
          .updateChartSong(song.bandId, chartId, songId: songId);
    } catch (e) {
      if (mounted) _showError(e);
    }
  }

  void _showError(Object e) {
    showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Could Not Update Link'),
        content: Text(ErrorView.friendlyMessage(e)),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ── Unlink ───────────────────────────────────────────────────────────────

  Future<void> _showChartOptions(SongChartSummary chart) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final action = await showCupertinoModalPopup<_ChartAction>(
        context: context,
        builder: (sheetCtx) => CupertinoActionSheet(
          actions: [
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () =>
                  Navigator.of(sheetCtx).pop(_ChartAction.unlink),
              child: const Text('Unlink sheet music'),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.of(sheetCtx).pop(),
            child: const Text('Cancel'),
          ),
        ),
      );

      if (action == _ChartAction.unlink) {
        await _patch(chart.id, null);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Add flow ─────────────────────────────────────────────────────────────

  Future<void> _showAddPicker() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      List<Chart> charts;
      try {
        final state = await ref.read(libraryProvider.future);
        charts =
            state.charts.where((c) => c.bandId == song.bandId).toList();
      } catch (e) {
        if (mounted) _showError(e);
        return;
      }
      if (!mounted) return;

      final selection = await showCupertinoModalPopup<_PickerSelection>(
        context: context,
        builder: (sheetCtx) => _ChartPickerSheet(charts: charts, song: song),
      );

      if (selection == null || !mounted) return;

      switch (selection) {
        case _NewChartSelection():
          await _createNew();
        case _ChartSelection(:final chart):
          await _handleChartPicked(chart);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createNew() async {
    AuthState? authState;
    try {
      authState = await ref.read(authProvider.future);
    } catch (_) {
      authState = null;
    }
    BandSummary? band;
    if (authState is AuthAuthenticated) {
      final match = authState.bands.where((b) => b.id == song.bandId);
      band = match.isEmpty ? null : match.first;
    }

    if (band == null) {
      if (mounted) {
        _showError(const _PlainError("Could not find this band's library."));
      }
      return;
    }

    if (!mounted) return;
    context.push(
      '/library/new',
      extra: CreateChartArgs(band: band, initialSong: song),
    );
  }

  Future<void> _handleChartPicked(Chart chart) async {
    final linkedElsewhere =
        chart.song != null && chart.song!.id != song.id;

    if (!linkedElsewhere) {
      await _patch(chart.id, song.id);
      return;
    }

    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Move Sheet Music?'),
        content: Text(
          '"${chart.title}" is linked to "${chart.song!.title}". '
          'Move it to "${song.title}"?',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Move'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _patch(chart.id, song.id);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeaderRow(busy: _busy, onAdd: _showAddPicker),
        if (song.charts.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'No sheet music linked to this song yet.',
              style: TextStyle(fontSize: 14, color: context.secondaryText),
            ),
          )
        else
          ...song.charts.map(
            (chart) => _LinkedChartRow(
              chart: chart,
              busy: _busy,
              onTap: () => context.push(
                '/library/${chart.id}',
                extra: song.bandId,
              ),
              onOptions: () => _showChartOptions(chart),
            ),
          ),
      ],
    );
  }
}

/// An error whose [toString] is exactly [message], so
/// [ErrorView.friendlyMessage] surfaces it verbatim (it falls back to
/// `e.toString()` for non-[DioException] errors).
class _PlainError {
  const _PlainError(this.message);
  final String message;
  @override
  String toString() => message;
}

enum _ChartAction { unlink }

sealed class _PickerSelection {
  const _PickerSelection();
}

class _NewChartSelection extends _PickerSelection {
  const _NewChartSelection();
}

class _ChartSelection extends _PickerSelection {
  const _ChartSelection(this.chart);
  final Chart chart;
}

// ── Header ─────────────────────────────────────────────────────────────────

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.busy, required this.onAdd});

  final bool busy;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'SHEET MUSIC',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
                color: context.secondaryText,
              ),
            ),
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: CupertinoActivityIndicator(),
            )
          else
            Semantics(
              label: 'Add sheet music',
              button: true,
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                onPressed: onAdd,
                child: const Icon(CupertinoIcons.add, size: 20),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Linked chart row ─────────────────────────────────────────────────────────

class _LinkedChartRow extends StatelessWidget {
  const _LinkedChartRow({
    required this.chart,
    required this.busy,
    required this.onTap,
    required this.onOptions,
  });

  final SongChartSummary chart;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onOptions;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${chart.title}. Opens the sheet music detail.',
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        decoration: BoxDecoration(
          color:
              CupertinoColors.tertiarySystemBackground.resolveFrom(context),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: busy ? null : onTap,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
            ),
            Semantics(
              button: true,
              label: 'Sheet music options for ${chart.title}',
              child: CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: Size.zero,
                onPressed: busy ? null : onOptions,
                child: Icon(
                  CupertinoIcons.ellipsis,
                  size: 18,
                  color: context.secondaryText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Add picker sheet ─────────────────────────────────────────────────────────

class _ChartPickerSheet extends StatelessWidget {
  const _ChartPickerSheet({required this.charts, required this.song});

  final List<Chart> charts;
  final Song song;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground.resolveFrom(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(
                'Sheet music',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  _NewChartRow(
                    onTap: () => Navigator.of(context)
                        .pop(const _NewChartSelection()),
                  ),
                  for (final chart in charts)
                    _ChartPickerRow(
                      chart: chart,
                      song: song,
                      onTap: chart.song?.id == song.id
                          ? null
                          : () => Navigator.of(context)
                              .pop(_ChartSelection(chart)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NewChartRow extends StatelessWidget {
  const _NewChartRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: CupertinoColors.separator.resolveFrom(context),
              width: 0.5,
            ),
          ),
        ),
        child: Text(
          'New sheet music…',
          style: TextStyle(fontSize: 15, color: context.primaryText),
        ),
      ),
    );
  }
}

class _ChartPickerRow extends StatelessWidget {
  const _ChartPickerRow({
    required this.chart,
    required this.song,
    required this.onTap,
  });

  final Chart chart;
  final Song song;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isThisSong = chart.song?.id == song.id;
    final linkedElsewhere = chart.song != null && !isThisSong;

    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: CupertinoColors.separator.resolveFrom(context),
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    chart.title,
                    style: TextStyle(
                      fontSize: 15,
                      color: isThisSong
                          ? context.tertiaryText
                          : context.primaryText,
                    ),
                  ),
                  if (linkedElsewhere)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'Linked to ${chart.song!.title}',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.secondaryText,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (isThisSong)
              Icon(
                CupertinoIcons.checkmark,
                size: 18,
                color: context.secondaryText,
              ),
          ],
        ),
      ),
    );
  }
}
