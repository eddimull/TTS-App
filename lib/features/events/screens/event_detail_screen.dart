import 'dart:async';
import 'package:clock/clock.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../shared/providers/selected_band_provider.dart';
import '../../../shared/utils/time_format.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/status_chip.dart';
import '../../chat/widgets/comment_bar.dart';
import '../data/models/event_detail.dart';
import '../providers/events_provider.dart';
import '../widgets/event_glance_card.dart';
import 'roster_sheet.dart';
import '../widgets/event_sections/contact_row.dart';
import '../widgets/event_sections/flags_row.dart';
import '../widgets/event_sections/lodging_section.dart';
import '../widgets/event_sections/media_section.dart';
import '../widgets/event_sections/notes_attachments_section.dart';
import '../widgets/event_sections/performance_section.dart';
import '../widgets/event_sections/roster_summary_row.dart';
import '../widgets/event_sections/section_primitives.dart';
import '../widgets/event_sections/timeline_section.dart';
import '../widgets/event_sections/venue_card.dart';
import '../widgets/event_sections/wedding_section.dart';

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
  final _timelineKey = GlobalKey();

  EventDetail get event => widget.event;

  void _scrollToKey(GlobalKey key) {
    final keyContext = key.currentContext;
    if (keyContext == null) return;
    Scrollable.ensureVisible(
      keyContext,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _openTimeline() => _scrollToKey(_timelineKey);

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
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Date / Time
            InfoRow(
              icon: CupertinoIcons.calendar,
              label: 'Date',
              value: _formatDateAndTime(event.date, event.time),
            ),

            // Venue
            if (event.venueName != null && event.venueName!.isNotEmpty) ...[
              const SizedBox(height: 12),
              VenueCard(
                venueName: event.venueName!,
                venueAddress: event.venueAddress,
              ),
            ],

            // Event type + flags row
            if (_hasFlags) ...[
              const SizedBox(height: 16),
              FlagsRow(event: event),
            ],

            // At-a-glance card
            if (EventGlanceCard.hasContent(event)) ...[
              const SizedBox(height: 12),
              EventGlanceCard(
                event: event,
                onShowTimeTap: _openTimeline,
                onLodgingTap: (lodgingId) =>
                    context.push('/lodging/$lodgingId'),
              ),
            ],

            // Notes + Attachments (combined — band-internal files, read-only)
            if (NotesAndAttachmentsSection.hasContent(
                event.notes, event.attachments)) ...[
              const SizedBox(height: 20),
              const SectionHeader(title: 'Notes'),
              const SizedBox(height: 8),
              NotesAndAttachmentsSection(
                notesHtml: event.notes,
                attachments: event.attachments,
              ),
            ],

            // Timeline
            if (event.timeline.isNotEmpty || event.time != null) ...[
              SizedBox(height: 20, key: _timelineKey),
              const SectionHeader(title: 'Timeline'),
              const SizedBox(height: 8),
              TimelineSection(
                entries: event.timeline,
                eventDate: event.parsedDate,
                showTime: event.time,
                eventDateStr: event.date,
              ),
            ],

            // Lodging
            if (event.lodgings.isNotEmpty) ...[
              const SizedBox(height: 20),
              const SectionHeader(title: 'Lodging'),
              const SizedBox(height: 8),
              LodgingLinksSection(lodgings: event.lodgings),
            ],

            // Contacts
            if (event.contacts.isNotEmpty) ...[
              const SizedBox(height: 20),
              const SectionHeader(title: 'Contacts'),
              const SizedBox(height: 8),
              ...event.contacts.map((c) => ContactRow(contact: c)),
            ],

            // Roster
            if (event.members.isNotEmpty) ...[
              const SizedBox(height: 20),
              RosterSummaryRow(event: event, onTap: _openRoster),
            ],

            // Performance (songs / charts)
            if (event.performance != null &&
                (event.performance!.notes?.isNotEmpty == true ||
                    event.performance!.songs.isNotEmpty ||
                    event.performance!.charts.isNotEmpty)) ...[
              const SizedBox(height: 20),
              const SectionHeader(title: 'Performance'),
              const SizedBox(height: 8),
              PerformanceSection(performance: event.performance!),
            ],

            // Wedding details
            if (event.wedding != null &&
                (event.wedding!.onsite != null ||
                    event.wedding!.dances.isNotEmpty)) ...[
              const SizedBox(height: 20),
              const SectionHeader(title: 'Wedding Details'),
              const SizedBox(height: 8),
              WeddingSection(wedding: event.wedding!),
            ],

            // Live setlist join (state-driven CTA — shown only during an
            // active live session; the plain Setlist row lives in the ⋯ menu)
            if (event.liveSessionId != null) ...[
              const SizedBox(height: 20),
              LiveSetlistButton(eventKey: event.key),
            ],

            // Media (client-shared photos/files — writers can upload)
            if (event.media.isNotEmpty || event.canWrite) ...[
              const SizedBox(height: 20),
              MediaSection(
                media: event.media,
                eventKey: event.key,
                eventId: event.id,
                canWrite: event.canWrite,
              ),
            ],

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  bool get _hasFlags =>
      event.isPublic != null ||
      event.outside != null ||
      event.backlineProvided != null ||
      event.productionNeeded != null;

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

  String _formatDateAndTime(String date, String? time) =>
      formatDateWithTimeRange(date, time, null);
}
