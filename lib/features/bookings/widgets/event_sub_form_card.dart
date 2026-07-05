import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/models/booking_date_status.dart';
import '../data/models/event_draft.dart';
import '../data/venue_search_service.dart';
import '../providers/bookings_provider.dart';
import 'booking_calendar_picker.dart';
import 'venue_picker.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';

// ── Date/time formatting helpers ──────────────────────────────────────────────

/// Parses "YYYY-MM-DD" → DateTime (date only; time is midnight local).
/// Returns null if the string is malformed.
DateTime? _parseIsoDate(String s) {
  final parts = s.split('-');
  if (parts.length != 3) return null;
  final y = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final d = int.tryParse(parts[2]);
  if (y == null || m == null || d == null) return null;
  return DateTime(y, m, d);
}

/// Formats a DateTime to the wire format "YYYY-MM-DD".
String _formatIsoDate(DateTime dt) {
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  return '${dt.year}-$m-$d';
}

/// Parses "HH:mm" → ({hour, minute}) via a simple record.
/// Returns null if the string is null or malformed.
({int hour, int minute})? _parseHhMm(String? s) {
  if (s == null || s.isEmpty) return null;
  final parts = s.split(':');
  if (parts.length != 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  return (hour: h, minute: m);
}

/// Formats hour/minute to the wire format "HH:mm".
String _formatHhMm(int hour, int minute) =>
    '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

/// Formats a DateTime (treated as a time) to friendly "7:00 PM" style.
String _friendlyTime(int hour, int minute) {
  final dt = DateTime(2000, 1, 1, hour, minute);
  return DateFormat('h:mm a').format(dt);
}

/// Formats a DateTime to friendly "Sat, May 17, 2026" style.
String _friendlyDate(DateTime dt) => DateFormat('EEE, MMM d, y').format(dt);

// ── Platform capability guard ─────────────────────────────────────────────────

/// True on platforms where google_maps_flutter renders correctly.
bool get _mapsSupported => kIsWeb || Platform.isAndroid || Platform.isIOS;

// ── Picker bottom-sheet ───────────────────────────────────────────────────────

/// A standard Cupertino modal bottom sheet with a Done button on top.
/// Mirrors the `_PickerSheet` used in `booking_form_screen.dart` but lives
/// here so `EventSubFormCard` can open pickers without depending on the parent.
class _PickerSheet extends StatelessWidget {
  const _PickerSheet({
    required this.child,
    required this.onDone,
    this.height = 300,
  });

  final Widget child;
  final VoidCallback onDone;

  /// Sheet height — wheels fit in the 300 default; the reserved-dates
  /// calendar needs more room for its grid, legend and subtitle.
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      // Use a safe-area-aware background so the sheet looks correct on
      // devices with a home indicator (iPhone X+) and on web/Linux too.
      color: CupertinoColors.systemBackground.resolveFrom(context),
      child: Column(
        children: [
          // Toolbar row — only Done needed; cancel is via drag-dismiss.
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              CupertinoButton(
                onPressed: () {
                  onDone();
                  Navigator.of(context).pop();
                },
                child: const Text(
                  'Done',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

// ── Tappable picker row ───────────────────────────────────────────────────────

/// A row that looks like a form field but opens a Cupertino picker when tapped.
///
/// [label] is shown on the left. [value] is shown on the right (or
/// [placeholder] in secondary color if value is null). When [value] is
/// non-null and [onClear] is provided, a small ✕ button lets the user
/// remove the value.
class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.label,
    required this.value,
    required this.placeholder,
    required this.onTap,
    this.onClear,
    this.isWarning = false,
  });

  final String label;
  final String? value;
  final String placeholder;
  final VoidCallback onTap;

  /// If non-null, a clear button is shown when [value] is non-null.
  final VoidCallback? onClear;

  /// When true, the value text is tinted destructive-red to signal a problem.
  final bool isWarning;

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null;
    final valueColor = isWarning
        ? CupertinoColors.destructiveRed.resolveFrom(context)
        : CupertinoColors.label.resolveFrom(context);
    final placeholderColor =
        CupertinoColors.placeholderText.resolveFrom(context);

    return Semantics(
      button: true,
      label: '$label: ${value ?? placeholder}',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          // Match the vertical rhythm of the CupertinoTextField rows above/below.
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Row(
            children: [
              Text(
                label,
                style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                      fontSize: 14,
                    ),
              ),
              const Spacer(),
              Text(
                hasValue ? value! : placeholder,
                style: TextStyle(
                  fontSize: 14,
                  color: hasValue ? valueColor : placeholderColor,
                ),
              ),
              // Clear button — only shown when there is a value and clearing
              // is allowed (i.e. the field is nullable).
              if (hasValue && onClear != null) ...[
                const SizedBox(width: 6),
                Semantics(
                  button: true,
                  label: 'Clear $label',
                  child: GestureDetector(
                    onTap: onClear,
                    behavior: HitTestBehavior.opaque,
                    child: Icon(
                      CupertinoIcons.clear_circled_solid,
                      size: 16,
                      color: context.tertiaryText,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 4),
              Icon(
                CupertinoIcons.chevron_right,
                size: 14,
                color: context.tertiaryText,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Main card widget ──────────────────────────────────────────────────────────

/// Single event row inside the booking form. Cupertino-styled.
///
/// Converted to [ConsumerStatefulWidget] so it can read [venueSearchServiceProvider]
/// directly to drive the venue autosuggest flow without requiring the parent
/// screen to pass the service through.
///
/// The host screen wraps each draft in a local `_EventFormRow` (id+key+draft+
/// localKey) and passes the draft and a stable key (the row's id or localKey)
/// to this widget.
///
/// Each keystroke / picker selection calls [onChange], which makes the host
/// `setState` and rebuild this card; controllers are created in `initState`
/// so they persist across rebuilds, avoiding the iOS-visible text-reversal bug.
class EventSubFormCard extends ConsumerStatefulWidget {
  const EventSubFormCard({
    super.key,
    required this.bandId,
    this.excludeBookingId,
    required this.draft,
    required this.canDelete,
    this.saveError,
    required this.onChange,
    required this.onDelete,
    this.onRetryRow,
  });

  /// Band whose existing bookings mark reserved dates in the date picker.
  final int bandId;

  /// When editing an existing booking, its id — so the calendar doesn't
  /// flag the booking's own date as taken.
  final int? excludeBookingId;

  final EventDraft draft;
  final bool canDelete;
  final String? saveError;
  final ValueChanged<EventDraft> onChange;
  final VoidCallback onDelete;
  final VoidCallback? onRetryRow;

  @override
  ConsumerState<EventSubFormCard> createState() => _EventSubFormCardState();
}

class _EventSubFormCardState extends ConsumerState<EventSubFormCard> {
  late final TextEditingController _title;

  // Transient lat/lng for the map thumbnail.  NOT persisted to EventDraft —
  // EventDraft only carries venueName and venueAddress.  See follow-up note
  // in the implementation report about lat/lng persistence.
  double? _venueLat;
  double? _venueLng;

  // True while the venue search/map flow is open. Guards against a fast
  // double-tap pushing two VenueSearchSheet routes before the first settles.
  bool _venueFlowOpen = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.draft.title);
    // An existing booking opens with venueAddress but no session coordinates
    // (EventDraft carries no lat/lng). Geocode it once so the map thumbnail
    // shows for already-saved venues, not just ones picked this session.
    _geocodeExistingVenueIfNeeded();
  }

  @override
  void didUpdateWidget(EventSubFormCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync controllers only when the parent pushes a genuinely different
    // value (e.g. a retry or programmatic change), not on the echo of the
    // user's own keystroke — overwriting on the echo would reset the cursor.
    _syncIfChanged(_title, widget.draft.title);
    // If the venue address changed out from under us and we have no coords,
    // geocode the new address (covers programmatic draft replacement).
    if (oldWidget.draft.venueAddress != widget.draft.venueAddress) {
      _geocodeExistingVenueIfNeeded();
    }
  }

  /// One-shot geocode of an already-stored venue address so the preview
  /// thumbnail renders for existing bookings. No-op when coords are already
  /// known, there is no address, or maps are unsupported (Linux).
  Future<void> _geocodeExistingVenueIfNeeded() async {
    if (_venueLat != null) return;
    final address = widget.draft.venueAddress ?? '';
    if (address.isEmpty || !_mapsSupported) return;
    // geocodeAddress() returns null when the API key is unset — no guard here.
    final position = await geocodeAddress(address);
    if (!mounted || position == null) return;
    // Bail if the address changed while geocoding, or coords arrived elsewhere.
    if (_venueLat != null || (widget.draft.venueAddress ?? '') != address) {
      return;
    }
    setState(() {
      _venueLat = position.latitude;
      _venueLng = position.longitude;
    });
  }

  void _syncIfChanged(TextEditingController controller, String value) {
    if (controller.text != value) {
      controller.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    }
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  // ── Picker launchers ────────────────────────────────────────────────────────

  void _pickDate(BuildContext context) {
    // Parse the stored ISO string into a DateTime for the picker.
    // Fall back to today if parsing fails (shouldn't happen in practice).
    final initial = _parseIsoDate(widget.draft.date) ?? DateTime.now();
    DateTime selected = initial;

    showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => _PickerSheet(
        height: 480,
        onDone: () => widget.onChange(_copyWith(date: _formatIsoDate(selected))),
        child: StatefulBuilder(
          builder: (context, setSheetState) => Consumer(
            builder: (context, ref, _) {
              // Reserved dates load in the background; the calendar is fully
              // usable with an empty map while they arrive (or on error).
              final infoAsync =
                  ref.watch(bookingDateInfoProvider(widget.bandId));
              final raw = infoAsync.asData?.value ??
                  const <String, BookingDateInfo>{};
              // Don't flag the booking being edited on its own date.
              final statuses = widget.excludeBookingId == null
                  ? raw
                  : <String, BookingDateInfo>{
                      for (final e in raw.entries)
                        if (e.value.bookingId != widget.excludeBookingId)
                          e.key: e.value,
                    };
              return BookingCalendarPicker(
                selectedDate: selected,
                dateStatuses: statuses,
                onDateSelected: (d) => setSheetState(() => selected = d),
              );
            },
          ),
        ),
      ),
    );
  }

  void _pickTime(
    BuildContext context, {
    required bool isStartTime,
  }) {
    final currentStr =
        isStartTime ? widget.draft.startTime : widget.draft.endTime;
    final parsed = _parseHhMm(currentStr);

    // Default to 19:00 (7 PM) for start, 22:00 (10 PM) for end if unset —
    // reasonable defaults for a live music gig.
    final defaultHour = isStartTime ? 19 : 22;
    final initialHour = parsed?.hour ?? defaultHour;
    final initialMinute = parsed?.minute ?? 0;

    // CupertinoDatePicker in time mode needs a full DateTime; only H:m matters.
    final initialDt = DateTime(2000, 1, 1, initialHour, initialMinute);
    DateTime selectedDt = initialDt;

    showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => _PickerSheet(
        onDone: () {
          final hhmm = _formatHhMm(selectedDt.hour, selectedDt.minute);
          widget.onChange(isStartTime
              ? _copyWith(startTime: hhmm)
              : _copyWith(endTime: hhmm));
        },
        child: CupertinoDatePicker(
          mode: CupertinoDatePickerMode.time,
          use24hFormat: false, // Display 12h to users; store as 24h
          initialDateTime: initialDt,
          onDateTimeChanged: (dt) => selectedDt = dt,
        ),
      ),
    );
  }

  // ── Venue search flow ────────────────────────────────────────────────────────
  //
  // Three-step flow on iOS/Android/web:
  //   Step 1 — VenueSearchSheet → VenuePrediction (or free-typed name)
  //   Step 2 — geocodeAddress(prediction.address) → LatLng?
  //   Step 3 — VenueMapPickerScreen → VenueDetails (name/address/lat/lng)
  //
  // On Linux, step 3 is skipped; NoOpVenueSearchService returns [] so the
  // free-text row in VenueSearchSheet is the primary input path.
  //
  // Cancelling the map picker loops back to the search sheet (same query
  // pre-populated) rather than dropping all the way back to the card.

  Future<void> _openVenueSearch() async {
    // Ignore a re-entrant tap while the flow is already on screen.
    if (_venueFlowOpen) return;
    _venueFlowOpen = true;
    try {
      await _runVenueSearchFlow();
    } finally {
      _venueFlowOpen = false;
    }
  }

  Future<void> _runVenueSearchFlow() async {
    final service = ref.read(venueSearchServiceProvider);

    // Seed the search box with the stored venue name, or the address when
    // there is no name (e.g. an address-only venue from the API).
    final storedName = widget.draft.venueName ?? '';
    String lastQuery =
        storedName.isNotEmpty ? storedName : (widget.draft.venueAddress ?? '');

    while (true) {
      // Step 1 — search sheet returns a raw prediction or free-typed name.
      final prediction = await Navigator.of(context).push<VenuePrediction>(
        CupertinoPageRoute(
          builder: (_) => VenueSearchSheet(
            initialText: lastQuery,
            service: service,
          ),
        ),
      );
      if (prediction == null || !mounted) return; // user cancelled entirely

      // Free-typed prediction has an empty placeId.
      final isFreeText = prediction.placeId.isEmpty;

      if (!_mapsSupported || isFreeText) {
        // Linux or free-typed name: accept directly, no map step.
        widget.onChange(_copyWith(
          venueName: prediction.name,
          venueAddress: prediction.address.isEmpty ? null : prediction.address,
        ));
        setState(() {
          _venueLat = null;
          _venueLng = null;
        });
        return;
      }

      // Persist the query so that if we loop back the field is pre-populated.
      lastQuery = prediction.name;

      // Step 2 — geocode the address so the map picker has a starting position.
      // geocodeAddress() returns null when the API key is unset; the map
      // picker handles a null position by opening at world zoom.
      final initialPosition = await geocodeAddress(prediction.address);

      if (!mounted) return;

      // Step 3 — full-screen map picker with draggable marker.
      // Returns null when the user presses Cancel → loop back to search.
      final details = await Navigator.of(context).push<VenueDetails>(
        CupertinoPageRoute(
          builder: (_) => VenueMapPickerScreen(
            venueName: prediction.name,
            venueAddress: prediction.address,
            initialPosition: initialPosition,
          ),
        ),
      );

      if (!mounted) return;

      if (details == null) {
        // Cancel on the map picker — go back to search with the same query.
        continue;
      }

      widget.onChange(_copyWith(
        venueName: details.name,
        venueAddress: details.address.isEmpty ? null : details.address,
      ));
      setState(() {
        _venueLat = details.lat;
        _venueLng = details.lng;
      });
      return;
    }
  }

  void _clearVenue() {
    widget.onChange(_copyWith(venueName: null, venueAddress: null));
    setState(() {
      _venueLat = null;
      _venueLng = null;
    });
  }

  Future<void> _openInMaps() async {
    final address = widget.draft.venueAddress ?? '';
    final name = widget.draft.venueName ?? '';
    final Uri uri;
    if (_venueLat != null && _venueLng != null) {
      uri = Uri.parse('https://maps.google.com/?q=$_venueLat,$_venueLng');
    } else if (address.isNotEmpty) {
      uri = Uri.parse(
          'https://maps.google.com/?q=${Uri.encodeComponent(address)}');
    } else if (name.isNotEmpty) {
      // Free-typed venue with no address — search Maps by name.
      uri =
          Uri.parse('https://maps.google.com/?q=${Uri.encodeComponent(name)}');
    } else {
      return;
    }
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ── End-before-start validation ─────────────────────────────────────────────

  /// Returns true when both times are set AND endTime is strictly before
  /// startTime. This is a subtle warning, not a hard block.
  bool get _endBeforeStart {
    final start = _parseHhMm(widget.draft.startTime);
    final end = _parseHhMm(widget.draft.endTime);
    if (start == null || end == null) return false;
    final startMins = start.hour * 60 + start.minute;
    final endMins = end.hour * 60 + end.minute;
    return endMins < startMins;
  }

  // ── Convenience copyWith ────────────────────────────────────────────────────

  EventDraft _copyWith({
    String? title,
    String? date,
    // Use a sentinel to distinguish "pass null intentionally" from "not provided".
    Object? startTime = _sentinel,
    Object? endTime = _sentinel,
    Object? venueName = _sentinel,
    Object? venueAddress = _sentinel,
    String? price,
  }) {
    final draft = widget.draft;
    return EventDraft(
      title: title ?? draft.title,
      date: date ?? draft.date,
      startTime:
          startTime == _sentinel ? draft.startTime : startTime as String?,
      endTime: endTime == _sentinel ? draft.endTime : endTime as String?,
      venueName: venueName == _sentinel ? draft.venueName : venueName as String?,
      venueAddress:
          venueAddress == _sentinel ? draft.venueAddress : venueAddress as String?,
      price: price ?? draft.price,
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;

    // Pre-compute friendly display strings for date and times.
    final parsedDate = _parseIsoDate(draft.date);
    final friendlyDate =
        parsedDate != null ? _friendlyDate(parsedDate) : draft.date;

    final parsedStart = _parseHhMm(draft.startTime);
    final friendlyStart = parsedStart != null
        ? _friendlyTime(parsedStart.hour, parsedStart.minute)
        : null;

    final parsedEnd = _parseHhMm(draft.endTime);
    final friendlyEnd = parsedEnd != null
        ? _friendlyTime(parsedEnd.hour, parsedEnd.minute)
        : null;

    final endBeforeStart = _endBeforeStart;
    // A venue is "set" if it has a name OR an address. Events created via the
    // API can carry an address with no name; treating address-only as "no
    // venue" would hide that address and let it be silently overwritten.
    final venueName = draft.venueName ?? '';
    final venueAddress = draft.venueAddress ?? '';
    final hasVenue = venueName.isNotEmpty || venueAddress.isNotEmpty;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: CupertinoColors.separator.resolveFrom(context),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Card header: title preview + delete ───────────────────────────
          Row(
            children: [
              Expanded(
                child: Text(
                  draft.title.isEmpty ? 'Untitled event' : draft.title,
                  style:
                      CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                ),
              ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: widget.canDelete ? widget.onDelete : null,
                child: Icon(
                  CupertinoIcons.trash,
                  color: widget.canDelete
                      ? CupertinoColors.destructiveRed
                      : CupertinoColors.inactiveGray,
                ),
              ),
            ],
          ),

          // ── Save-failure banner ───────────────────────────────────────────
          if (widget.saveError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: GestureDetector(
                onTap: widget.onRetryRow,
                child: const Row(
                  children: [
                    Icon(
                      CupertinoIcons.exclamationmark_circle_fill,
                      color: CupertinoColors.destructiveRed,
                      size: 16,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Save failed — tap to retry',
                      style: TextStyle(
                        color: CupertinoColors.destructiveRed,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 8),

          // ── Title text field ──────────────────────────────────────────────
          CupertinoTextField(
            placeholder: 'Title',
            controller: _title,
            onChanged: (v) => widget.onChange(_copyWith(title: v)),
          ),

          // ── Thin divider between text fields and picker rows ──────────────
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Container(
              height: 0.5,
              color: CupertinoColors.separator.resolveFrom(context),
            ),
          ),

          // ── Date picker row ───────────────────────────────────────────────
          _PickerRow(
            label: 'Date',
            value: friendlyDate,
            placeholder: 'Select date',
            onTap: () => _pickDate(context),
            // Date is required; no clear button.
          ),

          // ── Thin divider ──────────────────────────────────────────────────
          Container(
            height: 0.5,
            color: CupertinoColors.separator.resolveFrom(context),
          ),

          // ── Start time picker row ─────────────────────────────────────────
          // Start time is required to create a booking — no clear button, and
          // the placeholder signals the requirement before the user hits save.
          _PickerRow(
            label: 'Start time',
            value: friendlyStart,
            placeholder: 'Required',
            onTap: () => _pickTime(context, isStartTime: true),
          ),

          // ── Thin divider ──────────────────────────────────────────────────
          Container(
            height: 0.5,
            color: CupertinoColors.separator.resolveFrom(context),
          ),

          // ── End time picker row ───────────────────────────────────────────
          _PickerRow(
            label: 'End time',
            value: friendlyEnd,
            placeholder: 'Set time',
            onTap: () => _pickTime(context, isStartTime: false),
            onClear: draft.endTime != null
                ? () => widget.onChange(_copyWith(endTime: null))
                : null,
            // Highlight red when end is before start.
            isWarning: endBeforeStart,
          ),

          // ── End-before-start inline warning ──────────────────────────────
          if (endBeforeStart)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Icon(
                    CupertinoIcons.exclamationmark_triangle_fill,
                    size: 13,
                    color: CupertinoColors.systemOrange.resolveFrom(context),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'End time is before start time',
                    style: TextStyle(
                      fontSize: 12,
                      color:
                          CupertinoColors.systemOrange.resolveFrom(context),
                    ),
                  ),
                ],
              ),
            ),

          // ── Venue ─────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              height: 0.5,
              color: CupertinoColors.separator.resolveFrom(context),
            ),
          ),

          if (!hasVenue)
            // Empty state: tappable row opens the search flow.
            Semantics(
              button: true,
              label: 'Search for a venue',
              child: GestureDetector(
                onTap: _openVenueSearch,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  child: Row(
                    children: [
                      Text(
                        'Venue',
                        style: CupertinoTheme.of(context)
                            .textTheme
                            .textStyle
                            .copyWith(fontSize: 14),
                      ),
                      const Spacer(),
                      Text(
                        'Search venue',
                        style: TextStyle(
                          fontSize: 14,
                          color: context.placeholderText,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        CupertinoIcons.search,
                        size: 15,
                        color: context.tertiaryText,
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            // Selected state: embedded map preview with venue info + actions.
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: VenuePreviewCard(
                // Display only: when there is no name, show the address in the
                // name slot so the venue is never invisible. The stored
                // EventDraft.venueName is left empty — this does not write the
                // address into the name field.
                venueName: venueName.isNotEmpty ? venueName : venueAddress,
                venueAddress: venueName.isNotEmpty ? venueAddress : '',
                lat: _venueLat,
                lng: _venueLng,
                onOpenMaps: _openInMaps,
                onChange: _openVenueSearch,
                onClear: _clearVenue,
              ),
            ),
        ],
      ),
    );
  }
}

// Sentinel value used to distinguish "explicitly pass null" from "not provided"
// in _copyWith, since Dart named parameters can't distinguish the two otherwise.
const Object _sentinel = Object();
