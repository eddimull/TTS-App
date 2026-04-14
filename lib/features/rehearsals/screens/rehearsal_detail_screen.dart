import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tts_bandmate/shared/utils/time_format.dart';
import 'package:tts_bandmate/shared/widgets/error_view.dart';
import '../data/models/rehearsal_detail.dart';
import '../data/rehearsals_repository.dart';
import '../providers/rehearsals_provider.dart';

class RehearsalDetailScreen extends ConsumerWidget {
  const RehearsalDetailScreen({
    super.key,
    this.rehearsalId,
    this.preloaded,
  }) : assert(rehearsalId != null || preloaded != null,
            'Provide rehearsalId or preloaded');

  final int? rehearsalId;
  final RehearsalDetail? preloaded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (preloaded != null) {
      return _RehearsalDetailView(rehearsal: preloaded!);
    }

    final detailAsync = ref.watch(rehearsalDetailProvider(rehearsalId!));

    return detailAsync.when(
      loading: () => const CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(),
        child: Center(child: CupertinoActivityIndicator()),
      ),
      error: (e, _) => CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(),
        child: ErrorView(
          message: ErrorView.friendlyMessage(e),
          onRetry: () =>
              ref.invalidate(rehearsalDetailProvider(rehearsalId!)),
        ),
      ),
      data: (rehearsal) => _RehearsalDetailView(rehearsal: rehearsal),
    );
  }
}

class _RehearsalDetailView extends ConsumerStatefulWidget {
  const _RehearsalDetailView({required this.rehearsal});

  final RehearsalDetail rehearsal;

  @override
  ConsumerState<_RehearsalDetailView> createState() =>
      _RehearsalDetailViewState();
}

class _RehearsalDetailViewState
    extends ConsumerState<_RehearsalDetailView> {
  late String? _notes;
  bool _editingNotes = false;
  bool _savingNotes = false;
  late TextEditingController _notesController;

  @override
  void initState() {
    super.initState();
    _notes = widget.rehearsal.notes;
    _notesController = TextEditingController(text: _notes ?? '');
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _saveNotes() async {
    final newNotes = _notesController.text.trim().isEmpty
        ? null
        : _notesController.text.trim();
    setState(() => _savingNotes = true);
    try {
      final repo = ref.read(rehearsalsRepositoryProvider);
      final saved = await repo.updateNotes(widget.rehearsal.id, newNotes);
      setState(() {
        _notes = saved?.isEmpty == true ? null : saved;
        _editingNotes = false;
      });
      if (mounted) {
        showCupertinoDialog(
          context: context,
          builder: (_) => CupertinoAlertDialog(
            title: const Text('Saved'),
            content: const Text('Notes saved successfully.'),
            actions: [
              CupertinoDialogAction(
                child: const Text('OK'),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        showCupertinoDialog(
          context: context,
          builder: (_) => CupertinoAlertDialog(
            title: const Text('Error'),
            content: Text('Failed to save notes: $e'),
            actions: [
              CupertinoDialogAction(
                child: const Text('OK'),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _savingNotes = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rehearsal = widget.rehearsal;

    final displayVenue =
        (rehearsal.venueName != null && rehearsal.venueName!.isNotEmpty)
            ? rehearsal.venueName!
            : (rehearsal.schedule.locationName != null &&
                    rehearsal.schedule.locationName!.isNotEmpty)
                ? rehearsal.schedule.locationName!
                : null;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(_formatDateShort(rehearsal.date)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_editingNotes)
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () {
                  _notesController.text = _notes ?? '';
                  setState(() => _editingNotes = true);
                },
                child: const Icon(CupertinoIcons.pencil),
              ),
            if (_editingNotes) ...[
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _savingNotes
                    ? null
                    : () => setState(() => _editingNotes = false),
                child: const Text('Cancel'),
              ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _savingNotes ? null : _saveNotes,
                child: _savingNotes
                    ? const CupertinoActivityIndicator()
                    : const Text('Save'),
              ),
            ],
          ],
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (rehearsal.isCancelled) ...[
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: CupertinoColors.systemRed.resolveFrom(context).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: CupertinoColors.systemRed.resolveFrom(context).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(CupertinoIcons.xmark_circle,
                      color: CupertinoColors.systemRed.resolveFrom(context), size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'This rehearsal has been cancelled.',
                    style: TextStyle(
                      color: CupertinoColors.systemRed.resolveFrom(context),
                      fontWeight: FontWeight.w500,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          _InfoRow(
            icon: CupertinoIcons.calendar,
            label: 'Date',
            value: _formatDateAndTime(rehearsal.date, rehearsal.time),
          ),
          if (displayVenue != null) ...[
            const SizedBox(height: 12),
            _InfoRow(
              icon: CupertinoIcons.location,
              label: 'Location',
              value: displayVenue,
            ),
          ],
          const SizedBox(height: 20),
          const Text('Notes',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (_editingNotes)
            CupertinoTextField(
              controller: _notesController,
              autofocus: true,
              maxLines: null,
              minLines: 3,
              placeholder: 'Add notes for this rehearsal…',
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
                borderRadius: BorderRadius.circular(8),
              ),
            )
          else if (_notes != null && _notes!.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_notes!, style: const TextStyle(fontSize: 15)),
            )
          else
            Text(
              'No notes yet. Tap the edit button to add some.',
              style: TextStyle(
                  fontSize: 13,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context)),
            ),
          const SizedBox(height: 20),
          const Text('Schedule',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rehearsal.schedule.name,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w500),
                ),
                if (rehearsal.schedule.locationName != null &&
                    rehearsal.schedule.locationName!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    rehearsal.schedule.locationName!,
                    style: TextStyle(
                        fontSize: 13,
                        color: CupertinoColors.secondaryLabel.resolveFrom(context)),
                  ),
                ],
              ],
            ),
          ),
          if (rehearsal.associatedBookings.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text('Associated Bookings',
                style:
                    TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ...rehearsal.associatedBookings
                .map((b) => _AssociatedBookingRow(booking: b)),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  String _formatDateShort(String? date) {
    if (date == null) return 'Rehearsal';
    try {
      return DateFormat('MMMM d, yyyy').format(DateTime.parse(date));
    } catch (_) {
      return date;
    }
  }

  String _formatDateAndTime(String? date, String? time) {
    if (date == null) return time != null ? toAmPm(time) : 'Date TBD';
    try {
      final dt = DateTime.parse(date);
      final dateStr = DateFormat('EEEE, MMMM d, yyyy').format(dt);
      if (time != null && time.isNotEmpty) return '$dateStr at ${toAmPm(time)}';
      return dateStr;
    } catch (_) {
      return time != null ? '$date at ${toAmPm(time)}' : date;
    }
  }

}

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
        Icon(icon, size: 20, color: CupertinoColors.secondaryLabel.resolveFrom(context)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      color: CupertinoColors.secondaryLabel.resolveFrom(context))),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(fontSize: 15)),
            ],
          ),
        ),
      ],
    );
  }
}

class _AssociatedBookingRow extends StatelessWidget {
  const _AssociatedBookingRow({required this.booking});

  final AssociatedBooking booking;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(CupertinoIcons.book,
              size: 20, color: CupertinoColors.secondaryLabel.resolveFrom(context)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(booking.name,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w500)),
                Text(
                  _formatDate(booking.date),
                  style: TextStyle(
                      fontSize: 13,
                      color: CupertinoColors.secondaryLabel.resolveFrom(context)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String date) {
    try {
      return DateFormat('MMMM d, yyyy').format(DateTime.parse(date));
    } catch (_) {
      return date;
    }
  }
}
