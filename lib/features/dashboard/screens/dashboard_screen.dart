import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Material, Theme, ThemeData;
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../../core/storage/hint_storage.dart';
import '../../../core/theme/context_colors.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/providers/selected_band_provider.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/error_view.dart';
import '../../auth/data/models/band_summary.dart';
import '../../bookings/utils/new_booking_navigation.dart';
import '../../bookings/widgets/create_booking_sheet.dart';
import '../../events/data/models/event_summary.dart';
import '../dashboard_list_filter.dart';
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
                leading: Semantics(
                  label: 'Operations menu',
                  button: true,
                  child: CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => context.push('/operations'),
                    child: const Icon(CupertinoIcons.line_horizontal_3),
                  ),
                ),
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
                              pushNewBookingForm(context, bandId);
                            },
                          ),
                        );
                      },
                      child: const Icon(CupertinoIcons.add),
                    ),
                    const SizedBox(width: 4),
                    Semantics(
                      label: 'Account',
                      button: true,
                      child: GestureDetector(
                        onTap: () => context.push('/account'),
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
                    ),
                  ],
                ),
              ),
              const SliverToBoxAdapter(child: _BookingsMovedHint()),
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
                  isLoadingOlder: state.isLoadingOlder,
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
                    // Lazily pull older events if we swiped past the loaded
                    // range. Fire-and-forget: the fetch updates provider state,
                    // which rebuilds the calendar; errors are handled inside.
                    unawaited(
                      ref
                          .read(dashboardProvider.notifier)
                          .ensureMonthLoaded(focused),
                    );
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

}

class _DashboardContent extends ConsumerStatefulWidget {
  const _DashboardContent({
    required this.events,
    required this.currentEvent,
    required this.isLoadingOlder,
    required this.focusedDay,
    required this.selectedDay,
    required this.onDaySelected,
    required this.onPageChanged,
  });

  final List<EventSummary> events;
  final EventSummary? currentEvent;
  final bool isLoadingOlder;
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

  bool _isInCurrentRange(EventSummary event) {
    final selectedDay = widget.selectedDay;
    if (selectedDay != null) {
      // When a day is selected, an event is "in range" if it falls on that
      // day OR is the next-upcoming event. The latter requires sorting and is
      // more expensive than worth it for the tiebreaker — fall back to the
      // simpler "any event >= selectedDay" check, which is sufficient for the
      // empty-state branching decision.
      return !event.parsedDate.isBefore(selectedDay);
    }
    // Mirror the list's "current month starts today" rule (shared helper) so
    // the filter-is-hiding-events empty state stays consistent with what the
    // list would actually show.
    final range = FocusedMonthRange.of(widget.focusedDay, DateTime.now());
    return range.contains(event.parsedDate);
  }

  List<EventSummary> _filterByDayOrMonth(List<EventSummary> events) {
    return dashboardListEvents(
      events: events,
      focusedDay: widget.focusedDay,
      selectedDay: widget.selectedDay,
      now: DateTime.now(),
    );
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
    // `filterIsHidingEvents` is true when the filter is the reason the list is
    // empty — i.e. there are events in the current range that are being hidden.
    final filterIsHidingEvents = filterState.isActive &&
        filtered.isEmpty &&
        widget.events.any(_isInCurrentRange);

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
        if (widget.isLoadingOlder)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CupertinoActivityIndicator()),
          ),
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
                  filterIsHidingEvents: filterIsHidingEvents,
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
    required this.filterIsHidingEvents,
    required this.onClearFilters,
  });

  final DateTime? selectedDay;
  final DateTime focusedDay;
  final bool filterIsHidingEvents;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    if (filterIsHidingEvents) {
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

/// One-release migration hint: Bookings left the tab bar in 1.13.
class _BookingsMovedHint extends ConsumerStatefulWidget {
  const _BookingsMovedHint();

  @override
  ConsumerState<_BookingsMovedHint> createState() => _BookingsMovedHintState();
}

class _BookingsMovedHintState extends ConsumerState<_BookingsMovedHint> {
  bool _dismissedNow = false;

  @override
  Widget build(BuildContext context) {
    final storage = ref.watch(hintStorageProvider).value;
    if (storage == null || _dismissedNow || storage.bookingsMovedDismissed) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: CupertinoColors.secondarySystemBackground.resolveFrom(context),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(CupertinoIcons.info_circle,
                size: 18,
                color: CupertinoColors.activeBlue.resolveFrom(context)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Bookings has moved — find it under ☰ Operations.',
                style: TextStyle(fontSize: 13, color: context.primaryText),
              ),
            ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(34, 34),
              onPressed: () {
                setState(() => _dismissedNow = true);
                storage.dismissBookingsMoved();
              },
              child: Semantics(
                label: 'Dismiss',
                button: true,
                child: Icon(CupertinoIcons.xmark,
                    size: 16, color: context.secondaryText),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
