import 'package:flutter/cupertino.dart';
import '../data/models/event_draft.dart';

/// Single event row inside the booking form. Cupertino-styled.
///
/// Owned by `booking_form_screen.dart`. The host screen wraps each draft
/// in a local `_EventFormRow` (id+key+draft+localKey) and passes the
/// draft and a stable key (the row's id or localKey) to this widget.
///
/// This is a [StatefulWidget] so it can own its [TextEditingController]s
/// across rebuilds. Each keystroke calls [onChange], which makes the host
/// `setState` and rebuild this card; if the controllers were created in
/// `build()` they would be reconstructed with the cursor at offset 0,
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
  late final TextEditingController _date;
  late final TextEditingController _startTime;
  late final TextEditingController _endTime;
  late final TextEditingController _venueName;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.draft.title);
    _date = TextEditingController(text: widget.draft.date);
    _startTime = TextEditingController(text: widget.draft.startTime ?? '');
    _endTime = TextEditingController(text: widget.draft.endTime ?? '');
    _venueName = TextEditingController(text: widget.draft.venueName ?? '');
  }

  @override
  void didUpdateWidget(EventSubFormCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync controllers only when the parent pushes a genuinely different
    // value (e.g. a retry or programmatic change), not on the echo of the
    // user's own keystroke — overwriting on the echo would reset the cursor.
    _syncIfChanged(_title, widget.draft.title);
    _syncIfChanged(_date, widget.draft.date);
    _syncIfChanged(_startTime, widget.draft.startTime ?? '');
    _syncIfChanged(_endTime, widget.draft.endTime ?? '');
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
    _date.dispose();
    _startTime.dispose();
    _endTime.dispose();
    _venueName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
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
          CupertinoTextField(
            placeholder: 'Title',
            controller: _title,
            onChanged: (v) => widget.onChange(_copyWith(title: v)),
          ),
          const SizedBox(height: 8),
          CupertinoTextField(
            placeholder: 'Date (YYYY-MM-DD)',
            controller: _date,
            onChanged: (v) => widget.onChange(_copyWith(date: v)),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: CupertinoTextField(
                  placeholder: 'Start (HH:mm)',
                  controller: _startTime,
                  onChanged: (v) =>
                      widget.onChange(_copyWith(startTime: v.isEmpty ? null : v)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: CupertinoTextField(
                  placeholder: 'End (HH:mm)',
                  controller: _endTime,
                  onChanged: (v) =>
                      widget.onChange(_copyWith(endTime: v.isEmpty ? null : v)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
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

  EventDraft _copyWith({
    String? title,
    String? date,
    String? startTime,
    String? endTime,
    String? venueName,
    String? venueAddress,
    String? price,
  }) {
    final draft = widget.draft;
    return EventDraft(
      title: title ?? draft.title,
      date: date ?? draft.date,
      startTime: startTime ?? draft.startTime,
      endTime: endTime ?? draft.endTime,
      venueName: venueName ?? draft.venueName,
      venueAddress: venueAddress ?? draft.venueAddress,
      price: price ?? draft.price,
    );
  }
}
