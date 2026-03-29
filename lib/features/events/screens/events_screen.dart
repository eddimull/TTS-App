import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/providers/selected_band_provider.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/error_view.dart';
import '../../dashboard/widgets/event_card.dart';
import '../data/models/event_summary.dart';
import '../providers/events_provider.dart';

enum _EventsFilter { upcoming, all }

class EventsScreen extends ConsumerStatefulWidget {
  const EventsScreen({super.key});

  @override
  ConsumerState<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends ConsumerState<EventsScreen> {
  _EventsFilter _filter = _EventsFilter.upcoming;

  @override
  Widget build(BuildContext context) {
    final bandAsync = ref.watch(selectedBandProvider);

    return AppScaffold(
      child: bandAsync.when(
        loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Scaffold(
          appBar: AppBar(title: const Text('Events')),
          body: ErrorView(message: 'Could not determine band.\n$e'),
        ),
        data: (bandId) {
          if (bandId == null) {
            return Scaffold(
              appBar: AppBar(title: const Text('Events')),
              body: const ErrorView(message: 'No band selected.'),
            );
          }
          return _EventsBody(bandId: bandId, filter: _filter, onFilterChanged: (f) {
            setState(() => _filter = f);
          });
        },
      ),
    );
  }
}

// ── Body ──────────────────────────────────────────────────────────────────────

class _EventsBody extends ConsumerWidget {
  const _EventsBody({
    required this.bandId,
    required this.filter,
    required this.onFilterChanged,
  });

  final int bandId;
  final _EventsFilter filter;
  final void Function(_EventsFilter) onFilterChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final params = BandEventsParams(bandId: bandId);
    final eventsAsync = ref.watch(bandEventsProvider(params));

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(bandEventsProvider(params).notifier).refresh(),
        child: CustomScrollView(
          slivers: [
            SliverAppBar.medium(
              title: const Text('Events'),
              centerTitle: false,
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(56),
                child: _FilterChips(
                  current: filter,
                  onChanged: onFilterChanged,
                ),
              ),
            ),
            eventsAsync.when(
              loading: () => const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => SliverFillRemaining(
                child: ErrorView(
                  message: 'Could not load events.\n$e',
                  onRetry: () =>
                      ref.read(bandEventsProvider(params).notifier).refresh(),
                ),
              ),
              data: (events) {
                final filtered = _applyFilter(events, filter);
                if (filtered.isEmpty) {
                  return const SliverFillRemaining(
                    child: _EmptyEvents(),
                  );
                }
                return SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final event = filtered[index];
                      return EventCard(
                        event: event,
                        onTap: () => _navigateToEvent(context, event),
                      );
                    },
                    childCount: filtered.length,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToEvent(BuildContext context, EventSummary event) {
    if (event.isRehearsal) {
      if (event.id != null) {
        context.push('/rehearsals/${event.id}');
      } else {
        context.push('/rehearsals/by-key/${event.key}');
      }
    } else {
      context.push('/events/${event.key}');
    }
  }

  List<EventSummary> _applyFilter(
    List<EventSummary> events,
    _EventsFilter filter,
  ) {
    final now = DateTime.now();
    final sorted = [...events]
      ..sort((a, b) => a.parsedDate.compareTo(b.parsedDate));

    return switch (filter) {
      _EventsFilter.upcoming =>
        sorted.where((e) => !e.parsedDate.isBefore(now)).toList(),
      _EventsFilter.all => sorted,
    };
  }
}

// ── Filter chips ──────────────────────────────────────────────────────────────

class _FilterChips extends StatelessWidget {
  const _FilterChips({
    required this.current,
    required this.onChanged,
  });

  final _EventsFilter current;
  final void Function(_EventsFilter) onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          FilterChip(
            label: const Text('Upcoming'),
            selected: current == _EventsFilter.upcoming,
            onSelected: (_) => onChanged(_EventsFilter.upcoming),
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('All'),
            selected: current == _EventsFilter.all,
            onSelected: (_) => onChanged(_EventsFilter.all),
          ),
        ],
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyEvents extends StatelessWidget {
  const _EmptyEvents();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.event_busy_outlined,
            size: 56,
            color: theme.colorScheme.primary.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            'No events found',
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
