import 'package:flutter/cupertino.dart';
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
        loading: () => const Center(child: CupertinoActivityIndicator()),
        error: (e, _) => CupertinoPageScaffold(
          navigationBar: const CupertinoNavigationBar(middle: Text('Events')),
          child: ErrorView(message: 'Could not determine band.\n$e'),
        ),
        data: (bandId) {
          if (bandId == null) {
            return const CupertinoPageScaffold(
              navigationBar:
                  CupertinoNavigationBar(middle: Text('Events')),
              child: ErrorView(message: 'No band selected.'),
            );
          }
          return _EventsBody(
            bandId: bandId,
            filter: _filter,
            onFilterChanged: (f) {
              setState(() => _filter = f);
            },
          );
        },
      ),
    );
  }
}

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

    return CupertinoPageScaffold(
      child: CustomScrollView(
      slivers: [
        CupertinoSliverRefreshControl(
          onRefresh: () =>
              ref.read(bandEventsProvider(params).notifier).refresh(),
        ),
        const CupertinoSliverNavigationBar(
          largeTitle: Text('Events'),
        ),
        SliverToBoxAdapter(
          child: _FilterPills(current: filter, onChanged: onFilterChanged),
        ),
        eventsAsync.when(
          loading: () => const SliverFillRemaining(
            child: Center(child: CupertinoActivityIndicator()),
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
              return const SliverFillRemaining(child: _EmptyEvents());
            }
            return SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => EventCard(
                  event: filtered[index],
                  onTap: () => _navigateToEvent(context, filtered[index]),
                ),
                childCount: filtered.length,
              ),
            );
          },
        ),
      ],
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
      List<EventSummary> events, _EventsFilter filter) {
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

class _FilterPills extends StatelessWidget {
  const _FilterPills({required this.current, required this.onChanged});
  final _EventsFilter current;
  final void Function(_EventsFilter) onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          _Pill(
            label: 'Upcoming',
            selected: current == _EventsFilter.upcoming,
            onTap: () => onChanged(_EventsFilter.upcoming),
          ),
          const SizedBox(width: 8),
          _Pill(
            label: 'All',
            selected: current == _EventsFilter.all,
            onTap: () => onChanged(_EventsFilter.all),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? CupertinoColors.systemBlue.resolveFrom(context)
              : CupertinoColors.tertiarySystemBackground.resolveFrom(context),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: selected
                ? CupertinoColors.white
                : CupertinoColors.label.resolveFrom(context),
          ),
        ),
      ),
    );
  }
}

class _EmptyEvents extends StatelessWidget {
  const _EmptyEvents();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(CupertinoIcons.calendar_badge_minus,
              size: 56, color: CupertinoColors.systemBlue),
          SizedBox(height: 16),
          Text(
            'No events found',
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
