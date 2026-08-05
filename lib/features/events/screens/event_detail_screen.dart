import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:timelines_plus/timelines_plus.dart';
import 'package:map_launcher/map_launcher.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../shared/providers/selected_band_provider.dart';
import '../../../shared/utils/time_format.dart';
import '../../../shared/widgets/auth_thumbnail.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/status_chip.dart';
import '../../chat/widgets/comment_bar.dart';
import '../../bookings/widgets/venue_picker.dart' show geocodeAddress, VenuePreviewCard;
import '../../contacts/contact_detail_screen.dart';
import '../../contacts/contact_ref.dart';
import '../../media/providers/upload_queue_provider.dart';
import '../../media/widgets/upload_queue_sheet.dart';
import '../data/models/event_detail.dart';
import '../../lodging/data/models/lodging.dart';
import '../providers/events_provider.dart';
import '../../../shared/widgets/attachment_widgets.dart';
import '../widgets/event_glance_card.dart';
import 'roster_sheet.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';

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
  final _rosterKey = GlobalKey();

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
            _InfoRow(
              icon: CupertinoIcons.calendar,
              label: 'Date',
              value: _formatDateAndTime(event.date, event.time),
            ),

            // Venue
            if (event.venueName != null && event.venueName!.isNotEmpty) ...[
              const SizedBox(height: 12),
              _VenueCard(
                venueName: event.venueName!,
                venueAddress: event.venueAddress,
              ),
            ],

            // Event type + flags row
            if (_hasFlags) ...[
              const SizedBox(height: 16),
              _FlagsRow(event: event),
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
            if (_NotesAndAttachmentsSection.hasContent(
                event.notes, event.attachments)) ...[
              const SizedBox(height: 20),
              const _SectionHeader(title: 'Notes'),
              const SizedBox(height: 8),
              _NotesAndAttachmentsSection(
                notesHtml: event.notes,
                attachments: event.attachments,
              ),
            ],

            // Timeline
            if (event.timeline.isNotEmpty || event.time != null) ...[
              SizedBox(height: 20, key: _timelineKey),
              const _SectionHeader(title: 'Timeline'),
              const SizedBox(height: 8),
              _TimelineSection(
                entries: event.timeline,
                eventDate: event.parsedDate,
                showTime: event.time,
                eventDateStr: event.date,
              ),
            ],

            // Lodging
            if (event.lodgings.isNotEmpty) ...[
              const SizedBox(height: 20),
              const _SectionHeader(title: 'Lodging'),
              const SizedBox(height: 8),
              _LodgingLinksSection(lodgings: event.lodgings),
            ],

            // Contacts
            if (event.contacts.isNotEmpty) ...[
              const SizedBox(height: 20),
              const _SectionHeader(title: 'Contacts'),
              const SizedBox(height: 8),
              ...event.contacts.map((c) => _ContactRow(contact: c)),
            ],

            // Roster
            if (event.members.isNotEmpty) ...[
              SizedBox(height: 20, key: _rosterKey),
              _RosterSummaryRow(event: event, onTap: _openRoster),
            ],

            // Performance (songs / charts)
            if (event.performance != null &&
                (event.performance!.notes?.isNotEmpty == true ||
                    event.performance!.songs.isNotEmpty ||
                    event.performance!.charts.isNotEmpty)) ...[
              const SizedBox(height: 20),
              const _SectionHeader(title: 'Performance'),
              const SizedBox(height: 8),
              _PerformanceSection(performance: event.performance!),
            ],

            // Wedding details
            if (event.wedding != null &&
                (event.wedding!.onsite != null || event.wedding!.dances.isNotEmpty)) ...[
              const SizedBox(height: 20),
              const _SectionHeader(title: 'Wedding Details'),
              const SizedBox(height: 8),
              _WeddingSection(wedding: event.wedding!),
            ],

            // Live setlist join (state-driven CTA — shown only during an
            // active live session; the plain Setlist row lives in the ⋯ menu)
            if (event.liveSessionId != null) ...[
              const SizedBox(height: 20),
              _LiveSetlistButton(eventKey: event.key),
            ],

            // Media (client-shared photos/files — writers can upload)
            if (event.media.isNotEmpty || event.canWrite) ...[
              const SizedBox(height: 20),
              _MediaSection(
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

  String _formatDateAndTime(String date, String? time) =>
      formatDateWithTimeRange(date, time, null);
}

// ── Venue card with map preview ───────────────────────────────────────────────

class _VenueCard extends StatefulWidget {
  const _VenueCard({required this.venueName, this.venueAddress});
  final String venueName;
  final String? venueAddress;

  @override
  State<_VenueCard> createState() => _VenueCardState();
}

class _VenueCardState extends State<_VenueCard> {
  double? _lat;
  double? _lng;

  @override
  void initState() {
    super.initState();
    _geocodeVenue();
  }

  Future<void> _geocodeVenue() async {
    final fullAddress = [
      widget.venueName,
      if (widget.venueAddress != null && widget.venueAddress!.isNotEmpty)
        widget.venueAddress!,
    ].join(', ');
    final position = await geocodeAddress(fullAddress);
    if (!mounted) return;
    setState(() {
      _lat = position?.latitude;
      _lng = position?.longitude;
    });
  }

  @override
  Widget build(BuildContext context) {
    return VenuePreviewCard(
      venueName: widget.venueName,
      venueAddress: widget.venueAddress ?? '',
      lat: _lat,
      lng: _lng,
      readOnly: true,
      onOpenMaps: () => _openVenueInMaps(
        context: context,
        venueName: widget.venueName,
        venueAddress: widget.venueAddress,
      ),
    );
  }
}

// ── Open-in-Maps helper ───────────────────────────────────────────────────────
//
// Geocodes the venue's full address (name + address) into coordinates, then
// hands them to [MapLauncher.showMarker]. The native iOS Apple Maps path of
// map_launcher ignores `extraParams` and pins the marker at whatever Coords
// it's given — so passing Coords(0, 0) lands the user at null island. We
// MUST resolve to real coords before launching.
//
// If geocoding fails (no network, missing API key, ambiguous address) we
// fall back to Google's documented universal Maps URL, which performs an
// address-text search and works reliably on both iOS and Android.

Future<void> _openVenueInMaps({
  required BuildContext context,
  required String venueName,
  required String? venueAddress,
}) async {
  final fullAddress = [
    venueName,
    if (venueAddress != null && venueAddress.isNotEmpty) venueAddress,
  ].join(', ');

  final position = await geocodeAddress(fullAddress);
  if (!context.mounted) return;

  // No coords — fall back to a search-by-address universal URL.
  if (position == null) {
    final searchUri = Uri.parse(
      'https://www.google.com/maps/search/?api=1'
      '&query=${Uri.encodeComponent(fullAddress)}',
    );
    if (await canLaunchUrl(searchUri)) {
      await launchUrl(searchUri, mode: LaunchMode.externalApplication);
    }
    return;
  }

  final coords = Coords(position.latitude, position.longitude);
  final availableMaps = await MapLauncher.installedMaps;
  if (!context.mounted) return;

  // No native maps installed (rare on iOS/Android) — fall back to web search.
  if (availableMaps.isEmpty) {
    final searchUri = Uri.parse(
      'https://www.google.com/maps/search/?api=1'
      '&query=${Uri.encodeComponent(fullAddress)}',
    );
    if (await canLaunchUrl(searchUri)) {
      await launchUrl(searchUri, mode: LaunchMode.externalApplication);
    }
    return;
  }

  if (availableMaps.length == 1) {
    await availableMaps.first.showMarker(coords: coords, title: venueName);
    return;
  }

  // Multiple map apps — let the user pick.
  await showCupertinoModalPopup<void>(
    context: context,
    builder: (ctx) => CupertinoActionSheet(
      actions: [
        for (final map in availableMaps)
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              map.showMarker(coords: coords, title: venueName);
            },
            child: Text(map.mapName),
          ),
      ],
      cancelButton: CupertinoActionSheetAction(
        onPressed: () => Navigator.pop(ctx),
        child: const Text('Cancel'),
      ),
    ),
  );
}

// ── Reusable layout helpers ───────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(10),
      ),
      child: child,
    );
  }
}

// ── Info row (icon + label + value) ──────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: context.secondaryText),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: context.secondaryText,
                ),
              ),
              if (value.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 15,
                    color: context.primaryText,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ── Flags row ─────────────────────────────────────────────────────────────────

class _FlagsRow extends StatelessWidget {
  const _FlagsRow({required this.event});
  final EventDetail event;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];

    if (event.isPublic != null) {
      chips.add(_FlagChip(
        label: event.isPublic! ? 'Public' : 'Private',
        icon: event.isPublic! ? CupertinoIcons.globe : CupertinoIcons.lock,
        active: event.isPublic!,
      ));
    }
    if (event.outside != null) {
      chips.add(_FlagChip(
        label: 'Outdoor',
        icon: CupertinoIcons.sun_max,
        active: event.outside!,
      ));
    }
    if (event.backlineProvided != null) {
      chips.add(_FlagChip(
        label: 'Backline',
        icon: CupertinoIcons.music_note_2,
        active: event.backlineProvided!,
      ));
    }
    if (event.productionNeeded != null) {
      chips.add(_FlagChip(
        label: 'Production',
        icon: CupertinoIcons.bolt,
        active: event.productionNeeded!,
      ));
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (int i = 0; i < chips.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            chips[i],
          ],
        ],
      ),
    );
  }
}

class _FlagChip extends StatelessWidget {
  const _FlagChip({required this.label, required this.icon, required this.active});
  final String label;
  final IconData icon;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active
        ? CupertinoColors.systemBlue.resolveFrom(context)
        : CupertinoColors.systemGrey.resolveFrom(context);
    final bg = active
        ? CupertinoColors.systemBlue.resolveFrom(context).withValues(alpha: 0.12)
        : CupertinoColors.systemGrey5.resolveFrom(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

// ── Timeline ──────────────────────────────────────────────────────────────────

class _TimelineSection extends StatefulWidget {
  const _TimelineSection({
    required this.entries,
    required this.eventDate,
    this.showTime,
    this.eventDateStr,
  });
  final List<EventTimelineEntry> entries;
  final DateTime eventDate;
  final String? showTime;
  final String? eventDateStr;

  @override
  State<_TimelineSection> createState() => _TimelineSectionState();
}

class _TimelineSectionState extends State<_TimelineSection> {
  late Timer _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  List<({bool isShowTime, EventTimelineEntry entry})> _buildRows() {
    final rows = <({bool isShowTime, EventTimelineEntry entry})>[
      for (final e in widget.entries) (isShowTime: false, entry: e),
    ];
    if (widget.showTime != null && widget.eventDateStr != null) {
      rows.add((
        isShowTime: true,
        entry: EventTimelineEntry(title: 'Show Time', time: '${widget.eventDateStr} ${widget.showTime}'),
      ));
    }
    rows.sort((a, b) {
      final aTime = a.entry.time;
      final bTime = b.entry.time;
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      final aDt = DateTime.tryParse(aTime);
      final bDt = DateTime.tryParse(bTime);
      if (aDt == null || bDt == null) return aTime.compareTo(bTime);
      return aDt.compareTo(bDt);
    });
    return rows;
  }

  // Returns the index of the "active" row: the last row whose time <= now,
  // as long as the next row hasn't started yet (or it's the last row).
  int _activeIndex(List<({bool isShowTime, EventTimelineEntry entry})> rows) {
    int active = -1;
    for (int i = 0; i < rows.length; i++) {
      final t = rows[i].entry.time;
      if (t == null) continue;
      final dt = DateTime.tryParse(t);
      if (dt != null && !dt.isAfter(_now)) active = i;
    }
    return active;
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = CupertinoColors.activeBlue.resolveFrom(context);
    final connectorColor = CupertinoColors.separator.resolveFrom(context);
    final rows = _buildRows();
    final activeIdx = _activeIndex(rows);

    return _Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: FixedTimeline.tileBuilder(
          theme: TimelineThemeData(
            nodePosition: 0.02,
            color: accentColor,
            indicatorTheme: const IndicatorThemeData(size: 10, position: 0.5),
            connectorTheme: ConnectorThemeData(thickness: 5, color: connectorColor),
          ),
          builder: TimelineTileBuilder.connected(
            itemCount: rows.length,
            contentsBuilder: (context, i) {
              final row = rows[i];
              final isPin = row.isShowTime;
              final isPast = activeIdx >= 0 && i < activeIdx;
              final isCurrent = i == activeIdx;
              final Color labelColor;
              final Color timeColor;
              if (isCurrent) {
                labelColor = accentColor;
                timeColor = accentColor;
              } else if (isPast) {
                labelColor = CupertinoColors.tertiaryLabel.resolveFrom(context);
                timeColor = CupertinoColors.tertiaryLabel.resolveFrom(context);
              } else if (isPin) {
                labelColor = accentColor;
                timeColor = accentColor;
              } else {
                labelColor = CupertinoColors.label.resolveFrom(context);
                timeColor = CupertinoColors.secondaryLabel.resolveFrom(context);
              }

              return Padding(
                padding: const EdgeInsets.only(top: 10, right: 0, left: 10, bottom: 10),
                child: Row(
                  children: [
                    Text(
                      toAmPm(row.entry.time, fallback: '—'),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Menlo',
                        color: timeColor,
                        decoration: isPast ? TextDecoration.lineThrough : null,
                        decorationColor: timeColor,
                      ),
                    ),
                    if (isNextDay(row.entry.time, widget.eventDate)) ...[
                      const SizedBox(width: 4),
                      const NextDayBadge(),
                    ],
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        row.entry.title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: (isPin || isCurrent) ? FontWeight.w600 : FontWeight.w400,
                          color: labelColor,
                          decoration: isPast ? TextDecoration.lineThrough : null,
                          decorationColor: labelColor,
                        ),
                      ),
                    ),
                    if (isCurrent)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'NOW',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: accentColor,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
            indicatorBuilder: (context, i) {
              final isPast = activeIdx >= 0 && i < activeIdx;
              final isCurrent = i == activeIdx;
              final color = (isPast)
                  ? CupertinoColors.tertiaryLabel.resolveFrom(context)
                  : accentColor;
              return DotIndicator(
                color: color,
                size: isCurrent ? 13 : 10,
                border: isCurrent
                    ? Border.all(color: accentColor, width: 2)
                    : null,
              );
            },
            connectorBuilder: (context, i, type) {
              final isPast = activeIdx >= 0 && i < activeIdx;
              final color = isPast
                  ? CupertinoColors.tertiaryLabel.resolveFrom(context)
                  : connectorColor;
              return SolidLineConnector(color: color, thickness: 1.5);
            },
          ),
        ),
      ),
    );
  }
}

// ── Notes + Attachments (combined section) ────────────────────────────────────

/// Bundles the free-text notes and band-internal file attachments into a
/// single "Notes" section. Long notes are clamped to 6 lines with a
/// "Show more"/"Show less" toggle, and attachments beyond the first 3 are
/// hidden behind a "Show all (N)" toggle. Both toggles are local state so
/// expanding one doesn't affect the other.
class _NotesAndAttachmentsSection extends StatefulWidget {
  const _NotesAndAttachmentsSection({
    this.notesHtml,
    this.attachments = const [],
  });

  final String? notesHtml;
  final List<EventAttachment> attachments;

  static const int _attachmentPreviewCount = 3;
  static const int _notesClampLines = 6;

  static bool hasContent(String? notesHtml, List<EventAttachment> attachments) =>
      (notesHtml != null && notesHtml.isNotEmpty) || attachments.isNotEmpty;

  @override
  State<_NotesAndAttachmentsSection> createState() =>
      _NotesAndAttachmentsSectionState();
}

class _NotesAndAttachmentsSectionState
    extends State<_NotesAndAttachmentsSection> {
  bool _notesExpanded = false;
  bool _attachmentsExpanded = false;

  String get _plainNotes {
    final html = widget.notesHtml ?? '';
    return html
        .replaceAll(RegExp(r'<br\s*/?>'), '\n')
        .replaceAll(RegExp(r'<p[^>]*>'), '')
        .replaceAll('</p>', '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .trim();
  }

  /// Cheap heuristic for "would this overflow 6 lines" without a
  /// LayoutBuilder/TextPainter measure pass: count explicit newlines plus
  /// an estimate of wrapped lines from character count.
  bool get _notesOverflow {
    final notes = _plainNotes;
    if (notes.isEmpty) return false;
    final estimatedLines =
        '\n'.allMatches(notes).length + notes.length ~/ 40;
    return estimatedLines > _NotesAndAttachmentsSection._notesClampLines;
  }

  @override
  Widget build(BuildContext context) {
    final notes = _plainNotes;
    final hasNotes = notes.isNotEmpty;
    final attachments = widget.attachments;
    final hasAttachments = attachments.isNotEmpty;
    final showNotesToggle = hasNotes && _notesOverflow;
    final visibleAttachments = _attachmentsExpanded
        ? attachments
        : attachments
            .take(_NotesAndAttachmentsSection._attachmentPreviewCount)
            .toList();
    final showAttachmentsToggle = attachments.length >
        _NotesAndAttachmentsSection._attachmentPreviewCount;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasNotes) ...[
            Text(
              notes,
              style: const TextStyle(fontSize: 15),
              maxLines: _notesExpanded
                  ? null
                  : _NotesAndAttachmentsSection._notesClampLines,
              overflow: _notesExpanded ? null : TextOverflow.ellipsis,
            ),
            if (showNotesToggle)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  onPressed: () =>
                      setState(() => _notesExpanded = !_notesExpanded),
                  child: Text(_notesExpanded ? 'Show less' : 'Show more'),
                ),
              ),
          ],
          if (hasNotes && hasAttachments)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: _Divider(),
            ),
          if (hasAttachments) ...[
            for (int i = 0; i < visibleAttachments.length; i++) ...[
              if (i > 0) const _Divider(),
              _AttachmentRow(
                attachment: visibleAttachments[i],
                imageAttachments: attachments
                    .where((a) => a.mimeType.startsWith('image/'))
                    .toList(),
              ),
            ],
            if (showAttachmentsToggle && !_attachmentsExpanded)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  onPressed: () => setState(() => _attachmentsExpanded = true),
                  child: Text('Show all (${attachments.length})'),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 0.5,
      color: CupertinoColors.separator.resolveFrom(context),
    );
  }
}

// ── Live setlist button ───────────────────────────────────────────────────────

class _LiveSetlistButton extends StatelessWidget {
  const _LiveSetlistButton({required this.eventKey});
  final String eventKey;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: CupertinoButton.filled(
        onPressed: () => context.push('/events/$eventKey/setlist/live'),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(CupertinoIcons.music_note, size: 18),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                'Join Live Setlist',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Performance ───────────────────────────────────────────────────────────────

class _PerformanceSection extends StatelessWidget {
  const _PerformanceSection({required this.performance});
  final Performance performance;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (performance.notes != null && performance.notes!.isNotEmpty) ...[
          _Card(child: Text(performance.notes!, style: const TextStyle(fontSize: 15))),
          const SizedBox(height: 8),
        ],
        if (performance.songs.isNotEmpty) ...[
          Text('Songs',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: context.secondaryText)),
          const SizedBox(height: 6),
          _Card(
            child: Column(
              children: [
                for (int i = 0; i < performance.songs.length; i++) ...[
                  if (i > 0)
                    Container(height: 0.5, color: CupertinoColors.separator.resolveFrom(context)),
                  _SongRow(index: i + 1, song: performance.songs[i]),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (performance.charts.isNotEmpty) ...[
          Text('Sheet music',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: context.secondaryText)),
          const SizedBox(height: 6),
          _Card(
            child: Column(
              children: [
                for (int i = 0; i < performance.charts.length; i++) ...[
                  if (i > 0)
                    Container(height: 0.5, color: CupertinoColors.separator.resolveFrom(context)),
                  _ChartRow(chart: performance.charts[i]),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _SongRow extends StatelessWidget {
  const _SongRow({required this.index, required this.song});
  final int index;
  final PerformanceSong song;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '$index.',
              style: TextStyle(
                  fontSize: 13,
                  color: context.secondaryText),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (song.title != null && song.title!.isNotEmpty)
                  Text(song.title!, style: const TextStyle(fontSize: 15)),
                if (song.url != null && song.url!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  GestureDetector(
                    onTap: () => _launch(song.url!),
                    child: Text(
                      song.url!,
                      style: TextStyle(
                          fontSize: 13,
                          color: CupertinoColors.activeBlue.resolveFrom(context)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _launch(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _ChartRow extends StatelessWidget {
  const _ChartRow({required this.chart});
  final PerformanceChart chart;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(CupertinoIcons.doc_text,
              size: 16,
              color: context.secondaryText),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(chart.title, style: const TextStyle(fontSize: 15)),
                if (chart.composer != null && chart.composer!.isNotEmpty)
                  Text(chart.composer!,
                      style: TextStyle(
                          fontSize: 13,
                          color: context.secondaryText)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Wedding ───────────────────────────────────────────────────────────────────

class _WeddingSection extends StatelessWidget {
  const _WeddingSection({required this.wedding});
  final WeddingDetail wedding;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (wedding.onsite != null) ...[
            Row(
              children: [
                Icon(
                  wedding.onsite!
                      ? CupertinoIcons.checkmark_circle_fill
                      : CupertinoIcons.xmark_circle_fill,
                  size: 16,
                  color: wedding.onsite!
                      ? CupertinoColors.systemGreen.resolveFrom(context)
                      : CupertinoColors.systemGrey.resolveFrom(context),
                ),
                const SizedBox(width: 8),
                Text(
                  wedding.onsite! ? 'Ceremony On-site' : 'Ceremony Off-site',
                  style: const TextStyle(fontSize: 15),
                ),
              ],
            ),
          ],
          if (wedding.onsite != null && wedding.dances.isNotEmpty) ...[
            Container(height: 0.5, margin: const EdgeInsets.symmetric(vertical: 10), color: CupertinoColors.separator.resolveFrom(context)),
          ],
          if (wedding.dances.isNotEmpty) ...[
            Text(
              'Special Dances',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: context.secondaryText),
            ),
            const SizedBox(height: 8),
            for (int i = 0; i < wedding.dances.length; i++) ...[
              if (i > 0)
                Container(height: 0.5, color: CupertinoColors.separator.resolveFrom(context)),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 140,
                      child: Text(
                        _formatDanceTitle(wedding.dances[i].title),
                        style: TextStyle(
                            fontSize: 13,
                            color: context.secondaryText),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        wedding.dances[i].data?.isNotEmpty == true
                            ? wedding.dances[i].data!
                            : 'TBD',
                        style: const TextStyle(fontSize: 15),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  String _formatDanceTitle(String raw) =>
      raw.replaceAll('_', ' ').split(' ').map((w) {
        if (w.isEmpty) return w;
        return w[0].toUpperCase() + w.substring(1);
      }).join(' ');
}

// ── Lodging ───────────────────────────────────────────────────────────────────

class _LodgingLinksSection extends StatelessWidget {
  const _LodgingLinksSection({required this.lodgings});
  final List<LodgingSummary> lodgings;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        children: [
          for (int i = 0; i < lodgings.length; i++) ...[
            if (i > 0)
              Container(
                  height: 0.5,
                  color: CupertinoColors.separator.resolveFrom(context)),
            _LodgingLinkRow(lodging: lodgings[i]),
          ],
        ],
      ),
    );
  }
}

class _LodgingLinkRow extends StatelessWidget {
  const _LodgingLinkRow({required this.lodging});
  final LodgingSummary lodging;

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('EEE, MMM d');
    final checkIn = lodging.parsedCheckIn;
    final checkOut = DateTime.tryParse(lodging.checkOutAt) ?? checkIn;
    final range = '${dateFmt.format(checkIn)} – ${dateFmt.format(checkOut)}';

    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: () => context.push('/lodging/${lodging.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(CupertinoIcons.bed_double, size: 18, color: context.secondaryText),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(lodging.name,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w500)),
                  Text(range,
                      style:
                          TextStyle(fontSize: 13, color: context.secondaryText)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(CupertinoIcons.chevron_right,
                size: 16, color: context.tertiaryText),
          ],
        ),
      ),
    );
  }
}

// ── Contacts ──────────────────────────────────────────────────────────────────

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.contact});
  final EventContact contact;

  void _openDetail(BuildContext context) {
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => ContactDetailScreen(
          contact: ContactRef(
            name: contact.name,
            email: contact.email,
            phone: contact.phone,
            role: contact.role,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _openDetail(context),
        child: _Card(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: CupertinoColors.systemBlue
                      .resolveFrom(context)
                      .withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    contact.name.isNotEmpty ? contact.name[0].toUpperCase() : '?',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: CupertinoColors.systemBlue.resolveFrom(context)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(contact.name,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w500)),
                    if (contact.role != null && contact.role!.isNotEmpty)
                      Text(contact.role!,
                          style: TextStyle(
                              fontSize: 13,
                              color: context.secondaryText)),
                    if (contact.phone != null && contact.phone!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      _ContactLink(
                        icon: CupertinoIcons.phone,
                        label: contact.phone!,
                        url: 'tel:${contact.phone!}',
                        context: context,
                      ),
                    ],
                    if (contact.email != null && contact.email!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      _ContactLink(
                        icon: CupertinoIcons.mail,
                        label: contact.email!,
                        url: 'mailto:${contact.email!}',
                        context: context,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  CupertinoIcons.chevron_right,
                  size: 16,
                  color: context.tertiaryText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContactLink extends StatelessWidget {
  const _ContactLink({
    required this.icon,
    required this.label,
    required this.url,
    required this.context,
  });
  final IconData icon;
  final String label;
  final String url;
  final BuildContext context;

  @override
  Widget build(BuildContext ctx) {
    return GestureDetector(
      onTap: () async {
        final uri = Uri.tryParse(url);
        if (uri != null) await launchUrl(uri);
      },
      child: Row(
        children: [
          Icon(icon,
              size: 13,
              color: CupertinoColors.activeBlue.resolveFrom(ctx)),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                  fontSize: 13,
                  color: CupertinoColors.activeBlue.resolveFrom(ctx)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Media (client-shared) ─────────────────────────────────────────────────────

/// A self-contained ConsumerStatefulWidget so it can read Riverpod providers
/// (bandId, uploadQueueProvider, eventDetailProvider) without touching the
/// parent StatelessWidget _EventDetailView.
class _MediaSection extends ConsumerStatefulWidget {
  const _MediaSection({
    required this.media,
    required this.eventKey,
    required this.eventId,
    required this.canWrite,
  });

  final List<EventMedia> media;
  final String eventKey;
  final int eventId;
  final bool canWrite;

  @override
  ConsumerState<_MediaSection> createState() => _MediaSectionState();
}

class _MediaSectionState extends ConsumerState<_MediaSection> {
  bool _enqueueing = false;

  Future<void> _pickAndUploadMedia() async {
    final bandId = ref.read(selectedBandProvider).value ?? 0;
    if (bandId == 0) return; // No active band — bail silently.

    final paths = await _pickMediaPaths();
    if (paths.isEmpty) return;

    setState(() => _enqueueing = true);
    try {
      for (final path in paths) {
        if (path == null) continue;
        await ref.read(uploadQueueProvider.notifier).enqueue(
              bandId: bandId,
              eventId: widget.eventId,
              file: File(path),
            );
      }
      // No invalidate here: enqueue is fire-and-forget, so uploads are still
      // in flight. The ref.listen in build() refreshes the grid when an
      // upload for this event actually finishes.
    } finally {
      if (mounted) setState(() => _enqueueing = false);
    }
  }

  /// Returns the on-disk paths of the media the user picked, or an empty list
  /// if they cancelled. On mobile, offers Photos/camera/file sources via an
  /// action sheet; on desktop/web, goes straight to the file picker (there is
  /// no Photos concept there). Every source yields real on-disk files, which
  /// the chunked, resumable upload queue streams regardless of size — so large
  /// videos are safe.
  Future<List<String?>> _pickMediaPaths() async {
    final bool useMobilePicker = !kIsWeb && (Platform.isIOS || Platform.isAndroid);
    if (!useMobilePicker) {
      return _pickFilePaths();
    }

    final String? choice = await showCupertinoModalPopup<String>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(sheetContext, 'library'),
            child: const Text('Photo/Video Library'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(sheetContext, 'camera'),
            child: const Text('Take Photo'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(sheetContext, 'file'),
            child: const Text('Choose File'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetContext, null),
          child: const Text('Cancel'),
        ),
      ),
    );

    switch (choice) {
      case 'library':
        // pickMultipleMedia returns both images and videos. imageQuality: 100
        // minimizes image compression (image_picker still re-encodes images;
        // videos pass through untouched).
        final picked = await ImagePicker().pickMultipleMedia(imageQuality: 100);
        return picked.map((x) => x.path).toList();
      case 'camera':
        // Camera photo capture, one item at a time.
        final shot = await ImagePicker().pickImage(
          source: ImageSource.camera,
          imageQuality: 100,
        );
        return shot == null ? const [] : [shot.path];
      case 'file':
        return _pickFilePaths();
      default:
        return const []; // Cancelled.
    }
  }

  /// The existing arbitrary-file picker, shared by mobile's "Choose File"
  /// action and the desktop/web path.
  Future<List<String?>> _pickFilePaths() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.any,
    );
    if (result == null || result.files.isEmpty) return const [];
    return result.files.map((f) => f.path).toList();
  }

  void _showQueueSheet(BuildContext context) {
    // showCupertinoModalPopup creates a new route with a fresh widget tree, so
    // the ProviderScope ancestor is lost. Re-attach the existing container via
    // UncontrolledProviderScope so the sheet reads the same upload queue.
    final container = ProviderScope.containerOf(context);
    showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => UncontrolledProviderScope(
        container: container,
        child: const UploadQueueSheet(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Refresh the event detail when a background upload for THIS event
    // finishes. We count done-tasks for this event in prev vs next and only
    // invalidate on the rising edge (a newly-done task), so we never loop:
    // invalidate → refetch → rebuild re-registers this listener, but the queue
    // state is unchanged, so the callback does not refire.
    ref.listen<List<UploadTask>>(uploadQueueProvider, (prev, next) {
      int doneForEvent(List<UploadTask>? list) =>
          list
              ?.where((t) =>
                  t.eventId == widget.eventId &&
                  t.status == UploadStatus.done)
              .length ??
          0;
      if (doneForEvent(next) > doneForEvent(prev)) {
        ref.invalidate(eventDetailProvider(widget.eventKey));
      }
    });

    final tasks = ref.watch(uploadQueueProvider);
    // Active tasks for this event (queued or uploading).
    final activeTasks = tasks.where((t) =>
        t.eventId == widget.eventId &&
        (t.status == UploadStatus.uploading ||
            t.status == UploadStatus.queued ||
            t.status == UploadStatus.paused)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section header row ──────────────────────────────────────────────
        Row(
          children: [
            const Expanded(
              child: _SectionHeader(title: 'Media (shared with clients)'),
            ),
            if (widget.canWrite)
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _enqueueing ? null : _pickAndUploadMedia,
                child: _enqueueing
                    ? const CupertinoActivityIndicator()
                    : const Icon(CupertinoIcons.cloud_upload),
              ),
          ],
        ),
        // ── Active-upload inline banner ─────────────────────────────────────
        if (activeTasks.isNotEmpty) ...[
          const SizedBox(height: 8),
          _ActiveUploadBanner(
            tasks: activeTasks,
            onTap: () => _showQueueSheet(context),
          ),
        ],
        const SizedBox(height: 8),
        // ── Media grid or empty hint ────────────────────────────────────────
        if (widget.media.isEmpty)
          Text(
            'No media yet',
            style: TextStyle(
              fontSize: 14,
              color: context.secondaryText,
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 4,
              mainAxisSpacing: 4,
            ),
            itemCount: widget.media.length,
            itemBuilder: (context, i) => _MediaGridCell(item: widget.media[i]),
          ),
      ],
    );
  }
}

// ── Active-upload inline banner ────────────────────────────────────────────────

class _ActiveUploadBanner extends StatelessWidget {
  const _ActiveUploadBanner({required this.tasks, required this.onTap});
  final List<UploadTask> tasks;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Show total progress as an average across active tasks.
    final avgProgress =
        tasks.isEmpty ? 0.0 : tasks.map((t) => t.progress).reduce((a, b) => a + b) / tasks.length;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: CupertinoColors.systemBlue.resolveFrom(context).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const CupertinoActivityIndicator(),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tasks.length == 1
                        ? 'Uploading 1 file…'
                        : 'Uploading ${tasks.length} files…',
                    style: TextStyle(
                      fontSize: 13,
                      color: CupertinoColors.systemBlue.resolveFrom(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: SizedBox(
                      height: 3,
                      child: Stack(
                        children: [
                          Container(
                            color: CupertinoColors.systemBlue
                                .resolveFrom(context)
                                .withValues(alpha: 0.25),
                          ),
                          FractionallySizedBox(
                            widthFactor: avgProgress.clamp(0.0, 1.0),
                            child: Container(
                              color: CupertinoColors.systemBlue.resolveFrom(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              CupertinoIcons.chevron_right,
              size: 14,
              color: CupertinoColors.systemBlue.resolveFrom(context),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Single media grid cell ─────────────────────────────────────────────────────

class _MediaGridCell extends StatelessWidget {
  const _MediaGridCell({required this.item});
  final EventMedia item;

  @override
  Widget build(BuildContext context) {
    final isImage = item.mimeType.startsWith('image/');
    final thumbUrl = item.thumbnailUrl.isNotEmpty
        ? resolveAttachmentUrl(item.thumbnailUrl)
        : '';

    if (isImage && thumbUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: AuthThumbnail(url: thumbUrl),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
        child: Center(
          child: Icon(
            attachmentIcon(item.mimeType),
            size: 28,
            color: context.secondaryText,
          ),
        ),
      ),
    );
  }
}

// ── Attachments ───────────────────────────────────────────────────────────────
// (Rendered inline inside _NotesAndAttachmentsSection above — no standalone
// card wrapper needed since both live in the same "Notes" section card.)

class _AttachmentRow extends StatelessWidget {
  const _AttachmentRow({
    required this.attachment,
    required this.imageAttachments,
  });
  final EventAttachment attachment;

  /// All image attachments in the parent list — used to resolve the lightbox
  /// start index when this row is an image.
  final List<EventAttachment> imageAttachments;

  @override
  Widget build(BuildContext context) {
    final isImage = attachment.mimeType.startsWith('image/');
    final resolvedUrl = resolveAttachmentUrl(attachment.url);

    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: () => _handleTap(context, isImage, resolvedUrl),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            // Thumbnail for images, icon for everything else
            SizedBox(
              width: 40,
              height: 40,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: isImage && resolvedUrl.isNotEmpty
                    ? AuthThumbnail(url: resolvedUrl)
                    : ColoredBox(
                        color: CupertinoColors.systemBlue
                            .resolveFrom(context)
                            .withValues(alpha: 0.12),
                        child: Center(
                          child: Icon(
                            attachmentIcon(attachment.mimeType),
                            size: 22,
                            color: CupertinoColors.systemBlue
                                .resolveFrom(context),
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    attachment.filename,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w400),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    attachment.formattedSize,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              CupertinoIcons.chevron_right,
              size: 16,
              color: context.tertiaryText,
            ),
          ],
        ),
      ),
    );
  }

  void _handleTap(BuildContext context, bool isImage, String resolvedUrl) {
    if (isImage && imageAttachments.isNotEmpty) {
      // Find this attachment's index within the image-only list.
      final startIndex = imageAttachments.indexWhere((a) => a.id == attachment.id);
      Navigator.of(context).push(
        CupertinoPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => AttachmentLightbox(
            attachments: imageAttachments,
            startIndex: startIndex < 0 ? 0 : startIndex,
          ),
        ),
      );
    } else {
      if (resolvedUrl.isEmpty) return;
      final uri = Uri.tryParse(resolvedUrl);
      if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

// ── Roster summary row ─────────────────────────────────────────────────────

/// One-line roster summary replacing the old inline grouped section (Task 5).
/// Tapping it pushes the full [RosterSheet] with the grouped list + controls.
class _RosterSummaryRow extends StatelessWidget {
  const _RosterSummaryRow({required this.event, required this.onTap});

  final EventDetail event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final members = event.members;
    final total = members.length;
    final subCount = members.where((m) => m.isSub).length;
    final pendingCount = members.where((m) {
      final status = m.attendanceStatus?.toLowerCase();
      return !m.isFilled || status == null || status.isEmpty || status == 'pending';
    }).length;

    final countLabel = subCount > 0 ? '$total + $subCount sub' : '$total members';

    return _Card(
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        onPressed: onTap,
        child: Row(
          children: [
            Icon(CupertinoIcons.person_2, size: 18, color: context.secondaryText),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        countLabel,
                        style: TextStyle(fontSize: 15, color: context.primaryText),
                      ),
                      if (pendingCount > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: CupertinoColors.systemOrange.resolveFrom(context),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (pendingCount > 0)
                    Text(
                      '$pendingCount awaiting confirmation',
                      style: TextStyle(fontSize: 13, color: context.secondaryText),
                    ),
                ],
              ),
            ),
            Icon(CupertinoIcons.chevron_right, size: 16, color: context.tertiaryText),
          ],
        ),
      ),
    );
  }
}
