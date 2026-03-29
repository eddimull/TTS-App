import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';
import 'package:tts_bandmate/shared/widgets/app_scaffold.dart';
import 'package:tts_bandmate/shared/widgets/error_view.dart';
import '../data/models/rehearsal_schedule.dart';
import '../data/models/rehearsal_summary.dart';
import '../providers/rehearsals_provider.dart';

class RehearsalsScreen extends ConsumerWidget {
  const RehearsalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bandAsync = ref.watch(selectedBandProvider);

    return AppScaffold(
      child: bandAsync.when(
        loading: () => const Center(child: CupertinoActivityIndicator()),
        error: (e, _) => CupertinoPageScaffold(
          navigationBar:
              const CupertinoNavigationBar(middle: Text('Rehearsals')),
          child: ErrorView(message: 'Could not determine band.\n$e'),
        ),
        data: (bandId) {
          if (bandId == null) {
            return const CupertinoPageScaffold(
              navigationBar:
                  CupertinoNavigationBar(middle: Text('Rehearsals')),
              child: ErrorView(message: 'No band selected.'),
            );
          }
          return _RehearsalsBody(bandId: bandId);
        },
      ),
    );
  }
}

class _RehearsalsBody extends ConsumerWidget {
  const _RehearsalsBody({required this.bandId});

  final int bandId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedulesAsync = ref.watch(schedulesProvider(bandId));

    return CupertinoPageScaffold(
      child: CustomScrollView(
      slivers: [
        CupertinoSliverRefreshControl(
          onRefresh: () async => ref.invalidate(schedulesProvider(bandId)),
        ),
        const CupertinoSliverNavigationBar(
          largeTitle: Text('Rehearsals'),
        ),
        schedulesAsync.when(
          loading: () => const SliverFillRemaining(
            child: Center(child: CupertinoActivityIndicator()),
          ),
          error: (e, _) => SliverFillRemaining(
            child: ErrorView(
              message: 'Could not load rehearsal schedules.\n$e',
              onRetry: () => ref.invalidate(schedulesProvider(bandId)),
            ),
          ),
          data: (schedules) {
            if (schedules.isEmpty) {
              return const SliverFillRemaining(
                child: _EmptyRehearsals(),
              );
            }
            return SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) =>
                    _ScheduleTile(schedule: schedules[index]),
                childCount: schedules.length,
              ),
            );
          },
        ),
      ],
      ),
    );
  }
}

class _ScheduleTile extends StatelessWidget {
  const _ScheduleTile({required this.schedule});

  final RehearsalSchedule schedule;

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      if (schedule.locationName != null &&
          schedule.locationName!.isNotEmpty)
        schedule.locationName!,
      if (schedule.frequency != null && schedule.frequency!.isNotEmpty)
        _capitalise(schedule.frequency!),
    ].join(' · ');

    return _CupertinoExpandable(
      title: Text(
        schedule.name,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
      ),
      subtitle: subtitle.isNotEmpty
          ? Text(
              subtitle,
              style: const TextStyle(
                  fontSize: 13, color: CupertinoColors.secondaryLabel),
            )
          : null,
      children: schedule.upcomingRehearsals.isEmpty
          ? [
              const Padding(
                padding:
                    EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Text(
                  'No upcoming rehearsals.',
                  style: TextStyle(
                      fontSize: 13,
                      color: CupertinoColors.secondaryLabel),
                ),
              ),
            ]
          : schedule.upcomingRehearsals
              .map((r) => _RehearsalSubTile(rehearsal: r))
              .toList(),
    );
  }

  String _capitalise(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class _CupertinoExpandable extends StatefulWidget {
  const _CupertinoExpandable({
    required this.title,
    required this.children,
    this.subtitle,
  });
  final Widget title;
  final Widget? subtitle;
  final List<Widget> children;

  @override
  State<_CupertinoExpandable> createState() => _CupertinoExpandableState();
}

class _CupertinoExpandableState extends State<_CupertinoExpandable> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(CupertinoIcons.music_mic,
                      size: 20,
                      color: CupertinoColors.secondaryLabel),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        widget.title,
                        if (widget.subtitle != null) widget.subtitle!,
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(CupertinoIcons.chevron_right,
                        size: 16,
                        color: CupertinoColors.secondaryLabel),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            Container(height: 0.5, color: CupertinoColors.separator.resolveFrom(context)),
            ...widget.children,
          ],
        ],
      ),
    );
  }
}

class _RehearsalSubTile extends StatelessWidget {
  const _RehearsalSubTile({required this.rehearsal});

  final RehearsalSummary rehearsal;

  @override
  Widget build(BuildContext context) {
    final dateLabel =
        rehearsal.date != null ? _formatDate(rehearsal) : 'Date TBD';

    return GestureDetector(
      onTap: () =>
          GoRouter.of(context).push('/rehearsals/${rehearsal.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(
              rehearsal.isCancelled
                  ? CupertinoIcons.xmark_circle
                  : CupertinoIcons.checkmark_circle,
              size: 20,
              color: rehearsal.isCancelled
                  ? CupertinoColors.systemRed
                  : CupertinoColors.secondaryLabel,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dateLabel,
                    style: TextStyle(
                      fontSize: 15,
                      decoration: rehearsal.isCancelled
                          ? TextDecoration.lineThrough
                          : null,
                      color: rehearsal.isCancelled
                          ? CupertinoColors.secondaryLabel
                          : null,
                    ),
                  ),
                  if (rehearsal.isCancelled)
                    const Text(
                      'Cancelled',
                      style: TextStyle(
                          fontSize: 12,
                          color: CupertinoColors.systemRed),
                    ),
                ],
              ),
            ),
            const Icon(CupertinoIcons.chevron_right,
                size: 16, color: CupertinoColors.tertiaryLabel),
          ],
        ),
      ),
    );
  }

  String _formatDate(RehearsalSummary rehearsal) {
    try {
      final dateStr =
          DateFormat('EEEE, MMMM d').format(rehearsal.parsedDate);
      if (rehearsal.time != null && rehearsal.time!.isNotEmpty) {
        return '$dateStr at ${rehearsal.time}';
      }
      return dateStr;
    } catch (_) {
      return rehearsal.date ?? 'Date TBD';
    }
  }
}

class _EmptyRehearsals extends StatelessWidget {
  const _EmptyRehearsals();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(CupertinoIcons.music_mic,
              size: 56, color: CupertinoColors.systemBlue),
          SizedBox(height: 16),
          Text(
            'No rehearsal schedules',
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w500,
                color: CupertinoColors.secondaryLabel),
          ),
          SizedBox(height: 8),
          Text(
            'Check back later.',
            style: TextStyle(
                fontSize: 13, color: CupertinoColors.tertiaryLabel),
          ),
        ],
      ),
    );
  }
}
