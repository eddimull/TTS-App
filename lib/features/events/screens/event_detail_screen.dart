import 'dart:math' as math;
import 'package:clock/clock.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../shared/providers/selected_band_provider.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/status_chip.dart';
import '../../chat/widgets/comment_bar.dart';
import '../data/event_tabs.dart';
import '../data/models/event_detail.dart';
import '../providers/event_tab_storage.dart';
import '../providers/client_requests_provider.dart';
import '../providers/events_provider.dart';
import '../../finances/payout_editor/providers/payout_flow_provider.dart'
    show isSelectedBandOwnerProvider;
import '../../questionnaires/widgets/send_from_event.dart';
import '../widgets/event_header.dart';
import '../widgets/event_sections/questionnaire_undo_banner.dart';
import '../widgets/event_tabs/music_tab.dart';
import '../widgets/event_tabs/notes_tab.dart';
import '../widgets/event_tabs/overview_tab.dart';
import '../widgets/event_tabs/timeline_tab.dart';
import 'roster_sheet.dart';

class EventDetailScreen extends ConsumerWidget {
  const EventDetailScreen({
    super.key,
    required this.eventKey,
    this.parentBookingName,
    this.parentBookingId,
    this.parentBandId,
  });

  final String eventKey;
  final String? parentBookingName;
  final int? parentBookingId;
  final int? parentBandId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(eventDetailProvider(eventKey));

    return detailAsync.when(
      loading: () => const CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(),
        child: Center(child: CupertinoActivityIndicator()),
      ),
      error: (e, _) => CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(),
        child: ErrorView(
          message: ErrorView.friendlyMessage(e),
          onRetry: () => ref.invalidate(eventDetailProvider(eventKey)),
        ),
      ),
      data: (event) => _EventDetailView(
        event: event,
        parentBookingName: parentBookingName,
        parentBookingId: parentBookingId,
        parentBandId: parentBandId,
      ),
    );
  }
}

class _EventDetailView extends ConsumerStatefulWidget {
  const _EventDetailView({
    required this.event,
    this.parentBookingName,
    this.parentBookingId,
    this.parentBandId,
  });

  final EventDetail event;
  final String? parentBookingName;
  final int? parentBookingId;
  final int? parentBandId;

  @override
  ConsumerState<_EventDetailView> createState() => _EventDetailViewState();
}

class _EventDetailViewState extends ConsumerState<_EventDetailView> {
  /// Tab the user picked this visit; until then the remembered tab (or
  /// Overview) is used.
  EventTab? _picked;

  /// Measured height of the expanded header content. Seeded with a typical
  /// value so the first frame is close; corrected after layout.
  double _headerContentHeight = 300;

  EventDetail get event => widget.event;

  void _selectTab(EventTab tab) {
    setState(() => _picked = tab);
    ref.read(eventTabStorageProvider).value?.saveLastTab(tab);
  }

  void _onHeaderMeasured(double h) {
    if (!mounted || (h - _headerContentHeight).abs() < 0.5) return;
    setState(() => _headerContentHeight = h);
  }

  Widget _tabBody(EventTab tab, List<EventTab> tabs) {
    switch (tab) {
      case EventTab.overview:
        return OverviewTab(
          event: event,
          onOpenRoster: _openRoster,
          onShowTimeTap: tabs.contains(EventTab.timeline)
              ? () => _selectTab(EventTab.timeline)
              : null,
        );
      case EventTab.timeline:
        return TimelineTab(event: event);
      case EventTab.music:
        return MusicTab(event: event);
      case EventTab.notes:
        return NotesTab(event: event);
    }
  }

  /// Pushes the full-screen roster sheet.
  void _openRoster() {
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => RosterSheet(event: event),
      ),
    );
  }

  void _openMenu(
    BuildContext context, {
    required bool showBookingLink,
    required int? bookingBandId,
    required int? bookingId,
  }) {
    final container = ProviderScope.containerOf(context);
    showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => UncontrolledProviderScope(
        container: container,
        child: CupertinoActionSheet(
          actions: [
            if (showBookingLink)
              CupertinoActionSheetAction(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  context.push('/bookings/$bookingBandId/$bookingId');
                },
                child: const Text('Go to booking'),
              ),
            // Owners send questionnaires; same rule as the booking screen.
            if (showBookingLink &&
                bookingBandId != null &&
                bookingId != null &&
                ref.read(isSelectedBandOwnerProvider))
              CupertinoActionSheetAction(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  sendQuestionnaireFromEvent(context,
                      bandId: bookingBandId, bookingId: bookingId);
                },
                child: const Text('Send questionnaire'),
              ),
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(sheetContext);
                _openRoster();
              },
              child: const Text('Go to roster'),
            ),
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(sheetContext);
                context.push('/events/${event.key}/setlist');
              },
              child: const Text('Setlist'),
            ),
            // Anyone can join a running session; only writers can start one.
            if (event.liveSessionId != null || event.canWrite)
              CupertinoActionSheetAction(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  _openLiveSetlist();
                },
                child: Text(
                  event.liveSessionId != null ? 'Join live setlist' : 'Go live',
                ),
              ),
            if (event.canWrite)
              CupertinoActionSheetAction(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  context.push('/events/${event.key}/edit', extra: event);
                },
                child: const Text('Edit event'),
              ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(sheetContext),
            child: const Text('Cancel'),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Resolve the booking backlink. When opened from a booking, the parent
    // params carry the name + ids. Otherwise, derive it from the event's own
    // eventable fields (booking-backed events only) plus the active band.
    final selectedBandId = ref.watch(selectedBandProvider).value;
    final bool fromBooking =
        widget.parentBookingId != null && widget.parentBandId != null;
    final bool isBookingBacked = event.eventableType == 'Bookings' &&
        event.eventableId != null &&
        selectedBandId != null;

    final int? bookingBandId =
        fromBooking ? widget.parentBandId : selectedBandId;
    final int? bookingId =
        fromBooking ? widget.parentBookingId : event.eventableId;
    final bool showBookingLink = fromBooking || isBookingBacked;

    final stored = ref.watch(eventTabStorageProvider).value?.lastTab;
    // Client song picks also earn a Music tab. Only bookings have them.
    final requests = event.eventableType == 'Bookings'
        ? ref.watch(eventClientRequestsProvider(event.key))
        : null;
    // While the picks load, keep a remembered Music tab in place so the screen
    // doesn't open on Overview and then jump.
    final tabs = visibleTabs(
      event,
      hasClientRequests: requests != null &&
          (requests.value != null ||
              (requests.isLoading && stored == EventTab.music.name)),
    );
    final selected = (_picked != null && tabs.contains(_picked))
        ? _picked!
        : resolveInitialTab(stored, tabs);

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (event.status != null) ...[
              Semantics(
                label: 'Status: ${event.status}',
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: statusColor(context, event.status!),
                  ),
                ),
              ),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(event.title, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => _openMenu(
            context,
            showBookingLink: showBookingLink,
            bookingBandId: bookingBandId,
            bookingId: bookingId,
          ),
          child: const Icon(CupertinoIcons.ellipsis_circle),
        ),
      ),
      child: CommentBarBody(
        topic: TopicRef(kind: 'events', idOrKey: event.key),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final delegate = EventHeaderDelegate(
              event: event,
              tabs: tabs,
              selected: selected,
              onSelect: _selectTab,
              contentHeight: _headerContentHeight,
              onContentMeasured: _onHeaderMeasured,
              onGoLive: _openLiveSetlist,
            );
            // The nav bar is translucent, so the scaffold lets content run under
            // it and reports its height as top padding; a plain ListView would
            // apply that itself, a CustomScrollView with a pinned header must
            // be moved down explicitly.
            return MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: Padding(
                padding:
                    EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
                child: CustomScrollView(
                  slivers: [
                    SliverPersistentHeader(pinned: true, delegate: delegate),
                    SliverToBoxAdapter(
                      // Every tab is at least as tall as the space under the
                      // collapsed header, so switching from a long tab to a short
                      // one never pulls the header back open.
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: math.max(
                              0, constraints.maxHeight - delegate.minExtent),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                          // Every visible tab stays mounted (offstage when not
                          // selected) so state like the media upload listener
                          // survives switching tabs.
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // After sending questionnaire answers here; on
                              // every tab since the event may reopen on any.
                              QuestionnaireUndoBanner(event: event),
                              for (final tab in tabs)
                                Offstage(
                                  offstage: tab != selected,
                                  child: TickerMode(
                                    enabled: tab == selected,
                                    child: KeyedSubtree(
                                      key: ValueKey(tab),
                                      child: _tabBody(tab, tabs),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Opens the live setlist from the ⋯ menu. Going live away from gig day is
  /// allowed but confirmed first, since starting a session notifies the band.
  Future<void> _openLiveSetlist() async {
    final path = '/events/${event.key}/setlist/live';
    if (event.liveSessionId != null || _isGigDay(event.date)) {
      context.push(path);
      return;
    }
    final parsed = DateTime.tryParse(event.date);
    final when = parsed == null
        ? 'another day'
        : DateFormat('EEEE, MMM d').format(parsed);
    final proceed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Not gig day'),
        content: Text(
          'This event is on $when. Starting a live session will notify '
          'the band. Go live anyway?',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Go Live'),
          ),
        ],
      ),
    );
    if (proceed == true && mounted) context.push(path);
  }

  /// True on the event's date, and the day after so a gig running past
  /// midnight isn't flagged.
  static bool _isGigDay(String date) {
    final d = DateTime.tryParse(date);
    if (d == null) return false;
    final now = clock.now();
    final days = DateTime(now.year, now.month, now.day)
        .difference(DateTime(d.year, d.month, d.day))
        .inDays;
    return days == 0 || days == 1;
  }
}
