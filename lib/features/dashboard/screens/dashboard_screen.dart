import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/providers/selected_band_provider.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/error_view.dart';
import '../../events/data/models/event_summary.dart';
import '../providers/dashboard_provider.dart';
import '../widgets/event_card.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  @override
  Widget build(BuildContext context) {
    final authAsync = ref.watch(authProvider);
    final authState = authAsync.valueOrNull;
    final bandAsync = ref.watch(selectedBandProvider);
    final bandId = bandAsync.valueOrNull;

    final userName = authState is AuthAuthenticated ? authState.user.name : 'there';

    final bandName = () {
      if (authState is! AuthAuthenticated || bandId == null) return 'Your Band';
      try {
        return authState.bands.firstWhere((b) => b.id == bandId).name;
      } catch (_) {
        return 'Your Band';
      }
    }();

    final dashboardAsync = ref.watch(dashboardProvider);

    return AppScaffold(
      child: RefreshIndicator(
        onRefresh: () => ref.read(dashboardProvider.notifier).refresh(),
        child: CustomScrollView(
          slivers: [
            SliverAppBar.medium(
              title: Text(bandName),
              centerTitle: false,
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: GestureDetector(
                    onTap: () => _showLogoutDialog(context),
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor:
                          Theme.of(context).colorScheme.primaryContainer,
                      child: Text(
                        userName.isNotEmpty ? userName[0].toUpperCase() : '?',
                        style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            dashboardAsync.when(
              loading: () => const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => SliverFillRemaining(
                child: ErrorView(
                  message: 'Could not load dashboard.\n$e',
                  onRetry: () =>
                      ref.read(dashboardProvider.notifier).refresh(),
                ),
              ),
              data: (state) => _DashboardContent(
                events: state.events,
                focusedDay: _focusedDay,
                selectedDay: _selectedDay,
                onDaySelected: (selected, focused) {
                  setState(() {
                    _selectedDay =
                        isSameDay(_selectedDay, selected) ? null : selected;
                    _focusedDay = focused;
                  });
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showLogoutDialog(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref.read(authProvider.notifier).logout();
    }
  }
}

// ── Dashboard content ─────────────────────────────────────────────────────────

class _DashboardContent extends StatelessWidget {
  const _DashboardContent({
    required this.events,
    required this.focusedDay,
    required this.selectedDay,
    required this.onDaySelected,
  });

  final List<EventSummary> events;
  final DateTime focusedDay;
  final DateTime? selectedDay;
  final void Function(DateTime selected, DateTime focused) onDaySelected;

  List<EventSummary> get _filteredEvents {
    final now = DateTime.now();
    final cutoff = now.add(const Duration(days: 30));

    if (selectedDay != null) {
      final dayEvents = events
          .where((e) => isSameDay(e.parsedDate, selectedDay!))
          .toList();

      if (dayEvents.isNotEmpty) return dayEvents;

      // No events on selected day — show the next event after it.
      final later = events
          .where((e) => !e.parsedDate.isBefore(selectedDay!))
          .toList()
        ..sort((a, b) => a.parsedDate.compareTo(b.parsedDate));
      return later.take(1).toList();
    }

    return events
        .where(
          (e) =>
              !e.parsedDate.isBefore(now) &&
              !e.parsedDate.isAfter(cutoff),
        )
        .toList()
      ..sort((a, b) => a.parsedDate.compareTo(b.parsedDate));
  }

  Set<DateTime> get _eventDays {
    return events.map((e) => _normalise(e.parsedDate)).toSet();
  }

  DateTime _normalise(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  List<Object> _getEventsForDay(DateTime day) {
    return _eventDays.contains(_normalise(day)) ? [Object()] : [];
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredEvents;

    return SliverList(
      delegate: SliverChildListDelegate([
        _CalendarSection(
          focusedDay: focusedDay,
          selectedDay: selectedDay,
          getEventsForDay: _getEventsForDay,
          onDaySelected: onDaySelected,
        ),
        const SizedBox(height: 8),
        if (filtered.isEmpty)
          const _EmptyUpcomingEvents()
        else
          _EventsList(events: filtered),
        const SizedBox(height: 16),
      ]),
    );
  }
}

// ── Calendar ──────────────────────────────────────────────────────────────────

class _CalendarSection extends StatelessWidget {
  const _CalendarSection({
    required this.focusedDay,
    required this.selectedDay,
    required this.getEventsForDay,
    required this.onDaySelected,
  });

  final DateTime focusedDay;
  final DateTime? selectedDay;
  final List<Object> Function(DateTime day) getEventsForDay;
  final void Function(DateTime selected, DateTime focused) onDaySelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return TableCalendar<Object>(
      firstDay: DateTime.now().subtract(const Duration(days: 365)),
      lastDay: DateTime.now().add(const Duration(days: 365)),
      focusedDay: focusedDay,
      selectedDayPredicate: (day) => isSameDay(selectedDay, day),
      eventLoader: getEventsForDay,
      onDaySelected: onDaySelected,
      calendarFormat: CalendarFormat.month,
      availableCalendarFormats: const {CalendarFormat.month: 'Month'},
      headerStyle: const HeaderStyle(
        formatButtonVisible: false,
        titleCentered: true,
      ),
      calendarStyle: CalendarStyle(
        markerDecoration: BoxDecoration(
          color: colorScheme.primary,
          shape: BoxShape.circle,
        ),
        selectedDecoration: BoxDecoration(
          color: colorScheme.primary,
          shape: BoxShape.circle,
        ),
        todayDecoration: BoxDecoration(
          color: colorScheme.primaryContainer,
          shape: BoxShape.circle,
        ),
        todayTextStyle: TextStyle(color: colorScheme.onPrimaryContainer),
      ),
    );
  }
}

// ── Events list ───────────────────────────────────────────────────────────────

class _EventsList extends StatelessWidget {
  const _EventsList({required this.events});

  final List<EventSummary> events;

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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            'Upcoming Events',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
        ...events.map(
          (event) => EventCard(
            event: event,
            onTap: () => _navigateToEvent(context, event),
          ),
        ),
      ],
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyUpcomingEvents extends StatelessWidget {
  const _EmptyUpcomingEvents();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.calendar_today_outlined,
              size: 56,
              color: theme.colorScheme.primary.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              'No upcoming events',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your next 30 days are clear.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
