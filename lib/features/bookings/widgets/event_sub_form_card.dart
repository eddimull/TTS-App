import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import '../data/models/event_draft.dart';

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

// ── Picker bottom-sheet ───────────────────────────────────────────────────────

/// A standard Cupertino modal bottom sheet with a Done button on top.
/// Mirrors the `_PickerSheet` used in `booking_form_screen.dart` but lives
/// here so `EventSubFormCard` can open pickers without depending on the parent.
class _PickerSheet extends StatelessWidget {
  const _PickerSheet({required this.child, required this.onDone});

  final Widget child;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 300,
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
                      color: CupertinoColors.tertiaryLabel.resolveFrom(context),
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 4),
              Icon(
                CupertinoIcons.chevron_right,
                size: 14,
                color: CupertinoColors.tertiaryLabel.resolveFrom(context),
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
/// Owned by `booking_form_screen.dart`. The host screen wraps each draft
/// in a local `_EventFormRow` (id+key+draft+localKey) and passes the
/// draft and a stable key (the row's id or localKey) to this widget.
///
/// This is a [StatefulWidget] so it can own its [TextEditingController]s
/// across rebuilds. Each keystroke / picker selection calls [onChange],
/// which makes the host `setState` and rebuild this card; if the controllers
/// were created in `build()` they would be reconstructed on every rebuild,
/// causing typed text to come out reversed (an iOS-visible bug).
class EventSubFormCard extends StatefulWidget {
  const EventSubFormCard({
    super.key,
    required this.draft,
    required this.canDelete,
    this.saveError,
    required this.onChange,
    required this.onDelete,
    this.onRetryRow,
  });

  final EventDraft draft;
  final bool canDelete;
  final String? saveError;
  final ValueChanged<EventDraft> onChange;
  final VoidCallback onDelete;
  final VoidCallback? onRetryRow;

  @override
  State<EventSubFormCard> createState() => _EventSubFormCardState();
}

class _EventSubFormCardState extends State<EventSubFormCard> {
  late final TextEditingController _title;
  late final TextEditingController _venueName;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.draft.title);
    _venueName = TextEditingController(text: widget.draft.venueName ?? '');
  }

  @override
  void didUpdateWidget(EventSubFormCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync controllers only when the parent pushes a genuinely different
    // value (e.g. a retry or programmatic change), not on the echo of the
    // user's own keystroke — overwriting on the echo would reset the cursor.
    _syncIfChanged(_title, widget.draft.title);
    _syncIfChanged(_venueName, widget.draft.venueName ?? '');
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
    _venueName.dispose();
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
        onDone: () => widget.onChange(_copyWith(date: _formatIsoDate(selected))),
        child: CupertinoDatePicker(
          mode: CupertinoDatePickerMode.date,
          initialDateTime: initial,
          // Reasonable booking window: 5 years back to 5 years forward.
          minimumYear: DateTime.now().year - 5,
          maximumYear: DateTime.now().year + 5,
          onDateTimeChanged: (dt) => selected = dt,
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
    String? venueName,
    String? venueAddress,
    String? price,
  }) {
    final draft = widget.draft;
    return EventDraft(
      title: title ?? draft.title,
      date: date ?? draft.date,
      startTime:
          startTime == _sentinel ? draft.startTime : startTime as String?,
      endTime: endTime == _sentinel ? draft.endTime : endTime as String?,
      venueName: venueName ?? draft.venueName,
      venueAddress: venueAddress ?? draft.venueAddress,
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
          _PickerRow(
            label: 'Start time',
            value: friendlyStart,
            placeholder: 'Set time',
            onTap: () => _pickTime(context, isStartTime: true),
            onClear: draft.startTime != null
                ? () => widget.onChange(_copyWith(startTime: null))
                : null,
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
                      color: CupertinoColors.systemOrange.resolveFrom(context),
                    ),
                  ),
                ],
              ),
            ),

          // ── Thin divider ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Container(
              height: 0.5,
              color: CupertinoColors.separator.resolveFrom(context),
            ),
          ),

          // ── Venue name text field ─────────────────────────────────────────
          CupertinoTextField(
            placeholder: 'Venue name',
            controller: _venueName,
            onChanged: (v) =>
                widget.onChange(_copyWith(venueName: v.isEmpty ? null : v)),
          ),
        ],
      ),
    );
  }
}

// Sentinel value used to distinguish "explicitly pass null" from "not provided"
// in _copyWith, since Dart named parameters can't distinguish the two otherwise.
const Object _sentinel = Object();
