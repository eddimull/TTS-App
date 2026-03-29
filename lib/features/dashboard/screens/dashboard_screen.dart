import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Material, Theme, ThemeData;
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

    final userName =
        authState is AuthAuthenticated ? authState.user.name : 'there';

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
      child: CupertinoPageScaffold(
        child: CustomScrollView(
        slivers: [
          CupertinoSliverRefreshControl(
            onRefresh: () => ref.read(dashboardProvider.notifier).refresh(),
          ),
          CupertinoSliverNavigationBar(
            largeTitle: Text(bandName),
            trailing: GestureDetector(
              onTap: () => _showLogoutDialog(context),
              child: Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: CupertinoColors.systemBlue,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    userName.isNotEmpty ? userName[0].toUpperCase() : '?',
                    style: const TextStyle(
                      color: CupertinoColors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),
          dashboardAsync.when(
            loading: () => const SliverFillRemaining(
              child: Center(child: CupertinoActivityIndicator()),
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
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Log out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
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
      final dayEvents =
          events.where((e) => isSameDay(e.parsedDate, selectedDay!)).toList();

      if (dayEvents.isNotEmpty) return dayEvents;

      final later = events
          .where((e) => !e.parsedDate.isBefore(selectedDay!))
          .toList()
        ..sort((a, b) => a.parsedDate.compareTo(b.parsedDate));
      return later.take(1).toList();
    }

    return events
        .where(
          (e) =>
              !e.parsedDate.isBefore(now) && !e.parsedDate.isAfter(cutoff),
        )
        .toList()
      ..sort((a, b) => a.parsedDate.compareTo(b.parsedDate));
  }

  Set<DateTime> get _eventDays =>
      events.map((e) => _normalise(e.parsedDate)).toSet();

  DateTime _normalise(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  List<Object> _getEventsForDay(DateTime day) =>
      _eventDays.contains(_normalise(day)) ? [Object()] : [];

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
    final brightness = MediaQuery.platformBrightnessOf(context);
    return Theme(
      data: ThemeData(brightness: brightness),
      child: Material(
        color: CupertinoColors.systemBackground.resolveFrom(context),
        child: TableCalendar<Object>(
          firstDay: DateTime.now().subtract(const Duration(days: 365)),
          lastDay: DateTime.now().add(const Duration(days: 365)),
          focusedDay: focusedDay,
          selectedDayPredicate: (day) => isSameDay(selectedDay, day),
          eventLoader: getEventsForDay,
          onDaySelected: onDaySelected,
          calendarFormat: CalendarFormat.month,
          availableCalendarFormats: const {CalendarFormat.month: 'Month'},
          headerStyle:
              const HeaderStyle(formatButtonVisible: false, titleCentered: true),
          calendarStyle: const CalendarStyle(
            markerDecoration: BoxDecoration(
                color: CupertinoColors.systemBlue, shape: BoxShape.circle),
            selectedDecoration: BoxDecoration(
                color: CupertinoColors.systemBlue, shape: BoxShape.circle),
            todayDecoration: BoxDecoration(
                color: CupertinoColors.systemBlue, shape: BoxShape.circle),
            todayTextStyle: TextStyle(color: CupertinoColors.white),
          ),
        ),
      ),
    );
  }
}

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
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            'Upcoming Events',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
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

class _EmptyUpcomingEvents extends StatelessWidget {
  const _EmptyUpcomingEvents();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.calendar,
                size: 56, color: CupertinoColors.systemBlue),
            SizedBox(height: 16),
            Text(
              'No upcoming events',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                  color: CupertinoColors.secondaryLabel),
            ),
            SizedBox(height: 8),
            Text(
              'Your next 30 days are clear.',
              style: TextStyle(
                  fontSize: 13, color: CupertinoColors.tertiaryLabel),
            ),
          ],
        ),
      ),
    );
  }
}
