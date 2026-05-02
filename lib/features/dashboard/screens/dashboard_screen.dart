import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Material, Theme, ThemeData;
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/providers/selected_band_provider.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/error_view.dart';
import '../../auth/data/models/band_summary.dart';
import '../../bookings/widgets/create_booking_sheet.dart';
import '../../events/data/models/event_summary.dart';
import '../providers/calendar_filter_provider.dart';
import '../providers/dashboard_provider.dart';
import '../widgets/calendar_event_marker.dart';
import '../widgets/calendar_filter_button.dart';
import '../widgets/calendar_filter_sheet.dart';
import '../widgets/event_card.dart';
import '../widgets/live_now_card.dart';

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
    final authState = authAsync.value;
    final bandAsync = ref.watch(selectedBandProvider);
    final bandId = bandAsync.value;

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

    return CupertinoPageScaffold(
      child: Stack(
        children: [
          CustomScrollView(
            slivers: [
              CupertinoSliverRefreshControl(
                onRefresh: () => ref.read(dashboardProvider.notifier).refresh(),
              ),
              CupertinoSliverNavigationBar(
                largeTitle: Text(bandName),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () async {
                        await showCupertinoModalPopup<void>(
                          context: context,
                          builder: (sheetContext) => CreateBookingSheet(
                            onBandSelected: (bandId) {
                              Navigator.of(sheetContext).pop();
                              context.push('/bookings/$bandId/new');
                            },
                          ),
                        );
                      },
                      child: const Icon(CupertinoIcons.add),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
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
                            userName.isNotEmpty
                                ? userName[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              color: CupertinoColors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              dashboardAsync.when(
                loading: () => const SliverFillRemaining(
                  child: Center(child: CupertinoActivityIndicator()),
                ),
                error: (e, _) => SliverFillRemaining(
                  child: ErrorView(
                    message: ErrorView.friendlyMessage(e),
                    onRetry: () =>
                        ref.read(dashboardProvider.notifier).refresh(),
                  ),
                ),
                data: (state) => _DashboardContent(
                  events: state.events,
                  currentEvent: state.currentEvent,
                  focusedDay: _focusedDay,
                  selectedDay: _selectedDay,
                  onDaySelected: (selected, focused) {
                    setState(() {
                      _selectedDay =
                          isSameDay(_selectedDay, selected) ? null : selected;
                      _focusedDay = focused;
                    });
                  },
                  onPageChanged: (focused) {
                    setState(() {
                      _focusedDay = focused;
                      _selectedDay = null;
                    });
                  },
                ),
              ),
            ],
          ),
          // Floating filter button — sits above the bottom tab bar.
          Positioned(
            right: 16,
            bottom: 16 + MediaQuery.of(context).padding.bottom,
            child: CalendarFilterButton(
              onPressed: () => _openFilterSheet(context),
            ),
          ),
        ],
      ),
    );
  }

  void _openFilterSheet(BuildContext context) {
    final auth = ref.read(authProvider).value;
    final bands = (auth is AuthAuthenticated)
        ? auth.bands
        : const <BandSummary>[];
    showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => CalendarFilterSheet(bands: bands),
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

class _DashboardContent extends ConsumerStatefulWidget {
  const _DashboardContent({
    required this.events,
    required this.currentEvent,
    required this.focusedDay,
    required this.selectedDay,
    required this.onDaySelected,
    required this.onPageChanged,
  });

  final List<EventSummary> events;
  final EventSummary? currentEvent;
  final DateTime focusedDay;
  final DateTime? selectedDay;
  final void Function(DateTime selected, DateTime focused) onDaySelected;
  final void Function(DateTime focusedDay) onPageChanged;

  @override
  ConsumerState<_DashboardContent> createState() =>
      _DashboardContentState();
}

class _DashboardContentState extends ConsumerState<_DashboardContent> {
  int _slideDirection = 1;

  @override
  void didUpdateWidget(_DashboardContent old) {
    super.didUpdateWidget(old);
    final oldMonth = DateTime(old.focusedDay.year, old.focusedDay.month);
    final newMonth = DateTime(widget.focusedDay.year, widget.focusedDay.month);
    if (oldMonth != newMonth) {
      _slideDirection = newMonth.isAfter(oldMonth) ? 1 : -1;
    }
  }

  DateTime _normalise(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  List<EventSummary> _filterByDayOrMonth(List<EventSummary> events) {
    final focusedDay = widget.focusedDay;
    final selectedDay = widget.selectedDay;
    if (selectedDay != null) {
      final dayEvents =
          events.where((e) => isSameDay(e.parsedDate, selectedDay)).toList();
      if (dayEvents.isNotEmpty) return dayEvents;
      final later = events
          .where((e) => !e.parsedDate.isBefore(selectedDay))
          .toList()
        ..sort((a, b) => a.parsedDate.compareTo(b.parsedDate));
      return later.take(1).toList();
    }
    final monthStart = DateTime(focusedDay.year, focusedDay.month, 1);
    final monthEnd = DateTime(focusedDay.year, focusedDay.month + 1, 1);
    return events
        .where(
          (e) =>
              !e.parsedDate.isBefore(monthStart) &&
              e.parsedDate.isBefore(monthEnd),
        )
        .toList()
      ..sort((a, b) => a.parsedDate.compareTo(b.parsedDate));
  }

  @override
  Widget build(BuildContext context) {
    final filterState = ref.watch(calendarFilterProvider);
    final visibleEvents =
        widget.events.where(filterState.isEventVisible).toList();

    final eventsByDay = <DateTime, List<EventSummary>>{};
    for (final e in visibleEvents) {
      eventsByDay.putIfAbsent(_normalise(e.parsedDate), () => []).add(e);
    }

    final filtered = _filterByDayOrMonth(visibleEvents);
    final unfilteredForCurrentRange =
        _filterByDayOrMonth(widget.events);

    final focusedDay = widget.focusedDay;
    final selectedDay = widget.selectedDay;
    final currentEvent = widget.currentEvent;

    final eventsKey = ValueKey(
        '${focusedDay.year}-${focusedDay.month}-${selectedDay?.day ?? ''}-${filterState.activeCount}');
    final slideDir = _slideDirection;

    return SliverList(
      delegate: SliverChildListDelegate([
        if (currentEvent != null)
          LiveNowCard(
            event: currentEvent,
            onTap: () => _navigateToEvent(context, currentEvent),
          ),
        _CalendarSection(
          focusedDay: focusedDay,
          selectedDay: selectedDay,
          eventsByDay: eventsByDay,
          onDaySelected: widget.onDaySelected,
          onPageChanged: widget.onPageChanged,
        ),
        const SizedBox(height: 8),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          transitionBuilder: (child, animation) {
            final offsetTween = Tween<Offset>(
              begin: Offset(0.15 * slideDir, 0),
              end: Offset.zero,
            );
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: offsetTween.animate(
                  CurvedAnimation(parent: animation, curve: Curves.easeOut),
                ),
                child: child,
              ),
            );
          },
          child: filtered.isEmpty
              ? _EmptyState(
                  key: eventsKey,
                  selectedDay: selectedDay,
                  focusedDay: focusedDay,
                  filterIsActive: filterState.isActive,
                  filterIsHidingEverything: filterState.isActive &&
                      unfilteredForCurrentRange.isNotEmpty,
                  onClearFilters: () =>
                      ref.read(calendarFilterProvider.notifier).clear(),
                )
              : _EventsList(
                  key: eventsKey,
                  events: filtered,
                  focusedDay: focusedDay,
                ),
        ),
        // Extra bottom padding so the floating filter button doesn't cover
        // the last event card.
        const SizedBox(height: 80),
      ]),
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
}

class _CalendarSection extends StatelessWidget {
  const _CalendarSection({
    required this.focusedDay,
    required this.selectedDay,
    required this.eventsByDay,
    required this.onDaySelected,
    this.onPageChanged,
  });

  final DateTime focusedDay;
  final DateTime? selectedDay;
  final Map<DateTime, List<EventSummary>> eventsByDay;
  final void Function(DateTime selected, DateTime focused) onDaySelected;
  final void Function(DateTime focusedDay)? onPageChanged;

  DateTime _normalise(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  @override
  Widget build(BuildContext context) {
    final brightness = MediaQuery.platformBrightnessOf(context);
    return Theme(
      data: ThemeData(brightness: brightness),
      child: Material(
        color: CupertinoColors.systemBackground.resolveFrom(context),
        child: TableCalendar<EventSummary>(
          firstDay: DateTime.now().subtract(const Duration(days: 365)),
          lastDay: DateTime.now().add(const Duration(days: 365)),
          focusedDay: focusedDay,
          selectedDayPredicate: (day) => isSameDay(selectedDay, day),
          eventLoader: (day) => eventsByDay[_normalise(day)] ?? const [],
          onDaySelected: onDaySelected,
          onPageChanged: onPageChanged,
          rowHeight: 56,
          calendarFormat: CalendarFormat.month,
          availableCalendarFormats: const {CalendarFormat.month: 'Month'},
          headerStyle: const HeaderStyle(
              formatButtonVisible: false, titleCentered: true),
          calendarStyle: const CalendarStyle(
            selectedDecoration: BoxDecoration(
                color: CupertinoColors.systemBlue, shape: BoxShape.circle),
            todayDecoration: BoxDecoration(
                color: CupertinoColors.systemBlue, shape: BoxShape.circle),
            todayTextStyle: TextStyle(color: CupertinoColors.white),
          ),
          calendarBuilders: CalendarBuilders<EventSummary>(
            markerBuilder: (context, day, dayEvents) {
              if (dayEvents.isEmpty) return null;
              return Padding(
                padding: const EdgeInsets.only(top: 28),
                child: CalendarDayMarkers(events: dayEvents),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _EventsList extends StatelessWidget {
  const _EventsList({super.key, required this.events, required this.focusedDay});

  final List<EventSummary> events;
  final DateTime focusedDay;

  String get _monthLabel {
    final now = DateTime.now();
    if (focusedDay.year == now.year && focusedDay.month == now.month) {
      return 'Upcoming Events';
    }
    return 'Events in ${DateFormat('MMMM yyyy').format(focusedDay)}';
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            _monthLabel,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    super.key,
    required this.selectedDay,
    required this.focusedDay,
    required this.filterIsActive,
    required this.filterIsHidingEverything,
    required this.onClearFilters,
  });

  final DateTime? selectedDay;
  final DateTime focusedDay;
  final bool filterIsActive;
  final bool filterIsHidingEverything;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    if (filterIsActive && filterIsHidingEverything) {
      return Padding(
        padding:
            const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
        child: Column(
          children: [
            const EmptyStateView(
              icon: CupertinoIcons.line_horizontal_3_decrease,
              title: 'No events match your filters',
              subtitle: '',
            ),
            const SizedBox(height: 12),
            CupertinoButton.filled(
              onPressed: onClearFilters,
              child: const Text('Clear filters'),
            ),
          ],
        ),
      );
    }
    final selected = selectedDay;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      child: EmptyStateView(
        icon: CupertinoIcons.calendar,
        title: 'No events',
        subtitle: selected != null
            ? 'Nothing on ${DateFormat('MMMM d').format(selected)}.'
            : 'Nothing scheduled for ${DateFormat('MMMM').format(focusedDay)}.',
      ),
    );
  }
}
