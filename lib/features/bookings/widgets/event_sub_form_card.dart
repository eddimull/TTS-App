import 'package:flutter/cupertino.dart';
import '../data/models/event_draft.dart';

/// Single event row inside the booking form. Cupertino-styled.
///
/// Owned by `booking_form_screen.dart`. The host screen wraps each draft
/// in a local `_EventFormRow` (id+key+draft+localKey) and passes the
/// draft and a stable key (the row's id or localKey) to this widget.
class EventSubFormCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
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
                onPressed: canDelete ? onDelete : null,
                child: Icon(
                  CupertinoIcons.trash,
                  color: canDelete
                      ? CupertinoColors.destructiveRed
                      : CupertinoColors.inactiveGray,
                ),
              ),
            ],
          ),
          if (saveError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: GestureDetector(
                onTap: onRetryRow,
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
            controller: TextEditingController(text: draft.title),
            onChanged: (v) => onChange(_copyWith(title: v)),
          ),
          const SizedBox(height: 8),
          CupertinoTextField(
            placeholder: 'Date (YYYY-MM-DD)',
            controller: TextEditingController(text: draft.date),
            onChanged: (v) => onChange(_copyWith(date: v)),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: CupertinoTextField(
                  placeholder: 'Start (HH:mm)',
                  controller: TextEditingController(text: draft.startTime ?? ''),
                  onChanged: (v) =>
                      onChange(_copyWith(startTime: v.isEmpty ? null : v)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: CupertinoTextField(
                  placeholder: 'End (HH:mm)',
                  controller: TextEditingController(text: draft.endTime ?? ''),
                  onChanged: (v) =>
                      onChange(_copyWith(endTime: v.isEmpty ? null : v)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          CupertinoTextField(
            placeholder: 'Venue name',
            controller: TextEditingController(text: draft.venueName ?? ''),
            onChanged: (v) =>
                onChange(_copyWith(venueName: v.isEmpty ? null : v)),
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
