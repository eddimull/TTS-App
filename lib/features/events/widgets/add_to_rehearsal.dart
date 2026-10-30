import 'package:clock/clock.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';

import '../../rehearsals/data/models/rehearsal_summary.dart';
import '../data/models/event_detail.dart';
import '../data/rehearsal_prep.dart';
import '../providers/event_music_provider.dart';

/// Add to rehearsal: writes "Learn for Gig (Nov 7): Song, Song" into the
/// notes of the next rehearsal before the gig.
///
/// On the Music page ([single] false) it is a strip naming the rehearsals
/// before the gig, with the button when there is something to learn. On the
/// song sheet ([single] true) it is a full-width button with a caption.
class AddToRehearsalAction extends ConsumerStatefulWidget {
  const AddToRehearsalAction({
    super.key,
    required this.event,
    required this.titles,
    this.single = false,
  });

  final EventDetail event;
  final List<String> titles;
  final bool single;

  @override
  ConsumerState<AddToRehearsalAction> createState() =>
      _AddToRehearsalActionState();
}

class _AddToRehearsalActionState extends ConsumerState<AddToRehearsalAction> {
  bool _busy = false;
  String? _status;

  Future<void> _add(RehearsalSummary rehearsal, String label) async {
    setState(() {
      _busy = true;
      _status = null;
    });
    String status;
    try {
      final result = await addToRehearsal(
        ref,
        eventKey: widget.event.key,
        eventTitle: widget.event.title,
        eventDate: widget.event.parsedDate,
        rehearsal: rehearsal,
        titles: widget.titles,
      );
      status = switch (result) {
        AddedToRehearsal(:final added) => widget.single
            ? 'Added to $label'
            : 'Added ${added.length == 1 ? '1 song' : '${added.length} songs'} '
                'to $label',
        AlreadyOnRehearsal() => 'Already in the notes for $label',
      };
    } catch (_) {
      status = "Couldn't add it. Try again.";
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = status;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.event.parsedDate.isAfter(clock.now())) {
      return const SizedBox.shrink();
    }
    final async = ref.watch(rehearsalsBeforeEventProvider(widget.event.key));
    final list = async.value;
    if (list == null) return const SizedBox.shrink();

    final next = list.isEmpty ? null : list.first;
    final label = next == null ? null : rehearsalLabel(next);
    final canAdd = next != null && widget.titles.isNotEmpty;
    final secondary = TextStyle(fontSize: 13, color: context.secondaryText);

    final button = _busy
        ? const CupertinoActivityIndicator()
        : CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            minimumSize: const Size(44, 44),
            color: widget.single
                ? CupertinoColors.activeBlue.resolveFrom(context)
                : null,
            onPressed: canAdd ? () => _add(next, label!) : null,
            child: Text(
              'Add to rehearsal',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: widget.single ? CupertinoColors.white : null,
              ),
            ),
          );

    if (widget.single) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (canAdd) button,
          const SizedBox(height: 6),
          Text(
            _status ??
                (next == null
                    ? 'No rehearsal before this gig'
                    : 'Adds it to $label · the next rehearsal before this gig'),
            textAlign: TextAlign.center,
            style: secondary,
          ),
        ],
      );
    }

    final count = list.length;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
      decoration: BoxDecoration(
        color: CupertinoColors.secondarySystemGroupedBackground
            .resolveFrom(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(CupertinoIcons.calendar, size: 18, color: context.secondaryText),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              _status != null
                  ? TextSpan(text: _status)
                  : next == null
                      ? const TextSpan(text: 'No rehearsal before this gig')
                      : TextSpan(children: [
                          TextSpan(
                              text: count == 1
                                  ? '1 rehearsal before this gig: '
                                  : '$count rehearsals before this gig, next: '),
                          TextSpan(
                            text: label,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ]),
              style: TextStyle(fontSize: 14, color: context.primaryText),
            ),
          ),
          if (canAdd) button,
        ],
      ),
    );
  }
}
