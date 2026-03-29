import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
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

  /// Pass a pre-loaded detail (e.g. from by-key resolution) to skip the
  /// extra network fetch.
  final RehearsalDetail? preloaded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (preloaded != null) {
      return _RehearsalDetailView(rehearsal: preloaded!);
    }

    final detailAsync = ref.watch(rehearsalDetailProvider(rehearsalId!));

    return detailAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: ErrorView(
          message: 'Could not load rehearsal.\n$e',
          onRetry: () => ref.invalidate(rehearsalDetailProvider(rehearsalId!)),
        ),
      ),
      data: (rehearsal) => _RehearsalDetailView(rehearsal: rehearsal),
    );
  }
}

// ── Detail view ───────────────────────────────────────────────────────────────

class _RehearsalDetailView extends ConsumerStatefulWidget {
  const _RehearsalDetailView({required this.rehearsal});

  final RehearsalDetail rehearsal;

  @override
  ConsumerState<_RehearsalDetailView> createState() =>
      _RehearsalDetailViewState();
}

class _RehearsalDetailViewState extends ConsumerState<_RehearsalDetailView> {
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
    final newNotes =
        _notesController.text.trim().isEmpty ? null : _notesController.text.trim();
    setState(() => _savingNotes = true);
    try {
      final repo = ref.read(rehearsalsRepositoryProvider);
      final saved = await repo.updateNotes(widget.rehearsal.id, newNotes);
      setState(() {
        _notes = saved?.isEmpty == true ? null : saved;
        _editingNotes = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notes saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save notes: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingNotes = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rehearsal = widget.rehearsal;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final displayVenue =
        (rehearsal.venueName != null && rehearsal.venueName!.isNotEmpty)
            ? rehearsal.venueName!
            : (rehearsal.schedule.locationName != null &&
                    rehearsal.schedule.locationName!.isNotEmpty)
                ? rehearsal.schedule.locationName!
                : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(_formatDateShort(rehearsal.date)),
        centerTitle: false,
        actions: [
          if (!_editingNotes)
            IconButton(
              icon: const Icon(Icons.edit_note),
              tooltip: 'Edit notes',
              onPressed: () {
                _notesController.text = _notes ?? '';
                setState(() => _editingNotes = true);
              },
            ),
          if (_editingNotes) ...[
            TextButton(
              onPressed: _savingNotes ? null : () => setState(() => _editingNotes = false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: _savingNotes ? null : _saveNotes,
              child: _savingNotes
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Cancelled banner.
          if (rehearsal.isCancelled) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.cancel_outlined,
                      color: Colors.red.shade700, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'This rehearsal has been cancelled.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.red.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          // Date + time.
          _InfoRow(
            icon: Icons.calendar_today_outlined,
            label: 'Date',
            value: _formatDateAndTime(rehearsal.date, rehearsal.time),
          ),
          // Venue.
          if (displayVenue != null) ...[
            const SizedBox(height: 12),
            _InfoRow(
              icon: Icons.location_on_outlined,
              label: 'Location',
              value: displayVenue,
            ),
          ],
          // Notes section.
          const SizedBox(height: 20),
          Row(
            children: [
              Text(
                'Notes',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_editingNotes)
            TextField(
              controller: _notesController,
              autofocus: true,
              maxLines: null,
              minLines: 3,
              decoration: InputDecoration(
                hintText: 'Add notes for this rehearsal…',
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            )
          else if (_notes != null && _notes!.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _notes!,
                style: theme.textTheme.bodyMedium,
              ),
            )
          else
            Text(
              'No notes yet. Tap the edit button to add some.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          // Schedule info.
          const SizedBox(height: 20),
          Text(
            'Schedule',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rehearsal.schedule.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (rehearsal.schedule.locationName != null &&
                    rehearsal.schedule.locationName!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    rehearsal.schedule.locationName!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Associated bookings.
          if (rehearsal.associatedBookings.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              'Associated Bookings',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            ...rehearsal.associatedBookings.map(
              (booking) => _AssociatedBookingRow(booking: booking),
            ),
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
    if (date == null) return time ?? 'Date TBD';
    try {
      final dt = DateTime.parse(date);
      final dateStr = DateFormat('EEEE, MMMM d, yyyy').format(dt);
      if (time != null && time.isNotEmpty) return '$dateStr at $time';
      return dateStr;
    } catch (_) {
      return time != null ? '$date at $time' : date;
    }
  }
}

// ── Info row ──────────────────────────────────────────────────────────────────

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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(value, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Associated booking row ────────────────────────────────────────────────────

class _AssociatedBookingRow extends StatelessWidget {
  const _AssociatedBookingRow({required this.booking});

  final AssociatedBooking booking;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            Icons.book_outlined,
            size: 20,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  booking.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  _formatDate(booking.date),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
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
