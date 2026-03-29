import 'package:flutter/material.dart';
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
        loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Scaffold(
          appBar: AppBar(title: const Text('Rehearsals')),
          body: ErrorView(message: 'Could not determine band.\n$e'),
        ),
        data: (bandId) {
          if (bandId == null) {
            return Scaffold(
              appBar: AppBar(title: const Text('Rehearsals')),
              body: const ErrorView(message: 'No band selected.'),
            );
          }
          return _RehearsalsBody(bandId: bandId);
        },
      ),
    );
  }
}

// ── Body ──────────────────────────────────────────────────────────────────────

class _RehearsalsBody extends ConsumerWidget {
  const _RehearsalsBody({required this.bandId});

  final int bandId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedulesAsync = ref.watch(schedulesProvider(bandId));

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(schedulesProvider(bandId)),
        child: CustomScrollView(
          slivers: [
            const SliverAppBar.medium(
              title: Text('Rehearsals'),
              centerTitle: false,
            ),
            schedulesAsync.when(
              loading: () => const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
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
                    (context, index) => _ScheduleTile(
                      schedule: schedules[index],
                    ),
                    childCount: schedules.length,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ── Schedule tile (expandable) ────────────────────────────────────────────────

class _ScheduleTile extends StatelessWidget {
  const _ScheduleTile({required this.schedule});

  final RehearsalSchedule schedule;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final subtitle = [
      if (schedule.locationName != null && schedule.locationName!.isNotEmpty)
        schedule.locationName!,
      if (schedule.frequency != null && schedule.frequency!.isNotEmpty)
        _capitalise(schedule.frequency!),
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: Icon(
          Icons.fitness_center_outlined,
          color: colorScheme.onSurfaceVariant,
        ),
        title: Text(
          schedule.name,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: subtitle.isNotEmpty
            ? Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              )
            : null,
        children: schedule.upcomingRehearsals.isEmpty
            ? [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Text(
                    'No upcoming rehearsals.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ]
            : schedule.upcomingRehearsals
                .map(
                  (rehearsal) => _RehearsalSubTile(rehearsal: rehearsal),
                )
                .toList(),
      ),
    );
  }

  String _capitalise(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

// ── Rehearsal sub-tile ────────────────────────────────────────────────────────

class _RehearsalSubTile extends StatelessWidget {
  const _RehearsalSubTile({required this.rehearsal});

  final RehearsalSummary rehearsal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final dateLabel =
        rehearsal.date != null ? _formatDate(rehearsal) : 'Date TBD';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Icon(
        rehearsal.isCancelled
            ? Icons.cancel_outlined
            : Icons.event_available_outlined,
        size: 20,
        color: rehearsal.isCancelled
            ? Colors.red.shade400
            : colorScheme.onSurfaceVariant,
      ),
      title: Text(
        dateLabel,
        style: theme.textTheme.bodyMedium?.copyWith(
          decoration:
              rehearsal.isCancelled ? TextDecoration.lineThrough : null,
          color: rehearsal.isCancelled ? colorScheme.onSurfaceVariant : null,
        ),
      ),
      subtitle: rehearsal.isCancelled
          ? Text(
              'Cancelled',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.red.shade600,
              ),
            )
          : null,
      trailing: Icon(
        Icons.chevron_right,
        color: colorScheme.onSurfaceVariant,
      ),
      onTap: () => GoRouter.of(context).push('/rehearsals/${rehearsal.id}'),
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

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyRehearsals extends StatelessWidget {
  const _EmptyRehearsals();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.fitness_center_outlined,
            size: 56,
            color: theme.colorScheme.primary.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            'No rehearsal schedules',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Check back later.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
