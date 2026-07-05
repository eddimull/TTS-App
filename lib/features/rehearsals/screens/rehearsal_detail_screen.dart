import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tts_bandmate/shared/utils/time_format.dart';
import 'package:tts_bandmate/shared/widgets/error_view.dart';
import '../data/models/rehearsal_detail.dart';
import '../data/rehearsals_repository.dart';
import '../providers/rehearsals_provider.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';
import 'package:tts_bandmate/features/dashboard/providers/dashboard_provider.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';

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
          onRetry: () => ref.invalidate(rehearsalDetailProvider(rehearsalId!)),
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

class _RehearsalDetailViewState extends ConsumerState<_RehearsalDetailView> {
  late String? _notes;
  bool _editingNotes = false;
  bool _savingNotes = false;
  late TextEditingController _notesController;
  late RehearsalDetail _rehearsal;
  bool _togglingCancelled = false;

  @override
  void initState() {
    super.initState();
    _rehearsal = widget.rehearsal;
    _notes = widget.rehearsal.notes;
    _notesController = TextEditingController(text: _notes ?? '');
  }

  @override
  void didUpdateWidget(covariant _RehearsalDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.rehearsal, widget.rehearsal)) {
      _rehearsal = widget.rehearsal;
      // Keep notes in sync with the fresh data, but never clobber an edit
      // in progress (same invariant _setCancelled and _refreshNotes protect).
      if (!_editingNotes) {
        _notes = (widget.rehearsal.notes?.isEmpty ?? true)
            ? null
            : widget.rehearsal.notes;
        _notesController.text = _notes ?? '';
      }
    }
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
      final saved = await repo.updateNotes(_rehearsal.id, newNotes);
      setState(() {
        _notes = saved?.isEmpty == true ? null : saved;
        _editingNotes = false;
      });
      if (mounted) {
        showCupertinoDialog(
          context: context,
          builder: (dialogContext) => CupertinoAlertDialog(
            title: const Text('Saved'),
            content: const Text('Notes saved successfully.'),
            actions: [
              CupertinoDialogAction(
                child: const Text('OK'),
                onPressed: () => Navigator.pop(dialogContext),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        showCupertinoDialog(
          context: context,
          builder: (dialogContext) => CupertinoAlertDialog(
            title: const Text('Error'),
            content: Text('Failed to save notes: $e'),
            actions: [
              CupertinoDialogAction(
                child: const Text('OK'),
                onPressed: () => Navigator.pop(dialogContext),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _savingNotes = false);
    }
  }

  Future<void> _refreshNotes(int rehearsalId) async {
    try {
      final repo = ref.read(rehearsalsRepositoryProvider);
      final fresh = await repo.getRehearsalDetail(rehearsalId);
      if (!mounted) return;
      // Safe to overwrite the controller: the planner (the only caller) is
      // launched from the nav bar only when `!_editingNotes`, and it sits on
      // top of this screen, so a notes edit can't be in progress here.
      setState(() {
        _notes = (fresh.notes?.isEmpty ?? true) ? null : fresh.notes;
        _notesController.text = _notes ?? '';
      });
    } catch (_) {
      // Non-fatal: the plan was saved server-side; a manual refresh will show it.
    }
  }

  /// Upcoming (today or later) — mirrors _canPlan's date logic without the
  /// cancelled check.
  bool _isUpcoming(RehearsalDetail rehearsal) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = rehearsal.parsedDate;
    return !DateTime(d.year, d.month, d.day).isBefore(today);
  }

  Future<void> _setCancelled(bool cancel) async {
    setState(() => _togglingCancelled = true);
    try {
      final repo = ref.read(rehearsalsRepositoryProvider);
      final updated = await repo.setCancelled(_rehearsal.id, cancel);
      if (!mounted) return;
      setState(() {
        _rehearsal = updated;
        // Keep the notes state in sync with the fresh server copy, but never
        // clobber an edit in progress (same invariant _refreshNotes protects).
        if (!_editingNotes) {
          _notes = (updated.notes?.isEmpty ?? true) ? null : updated.notes;
          _notesController.text = _notes ?? '';
        }
      });
      _invalidateCaches();
    } catch (e) {
      if (mounted) {
        showCupertinoDialog(
          context: context,
          builder: (dialogContext) => CupertinoAlertDialog(
            title: const Text('Error'),
            content: Text(
                'Failed to ${cancel ? 'cancel' : 'restore'} the rehearsal: $e'),
            actions: [
              CupertinoDialogAction(
                child: const Text('OK'),
                onPressed: () => Navigator.pop(dialogContext),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _togglingCancelled = false);
    }
  }

  /// Refresh every surface that renders this rehearsal's cancelled state.
  /// Guarded: cache invalidation must never break the mutation UX.
  void _invalidateCaches() {
    try {
      ref.invalidate(rehearsalDetailProvider(_rehearsal.id));
      final bandId = ref.read(selectedBandProvider).value;
      if (bandId != null) ref.invalidate(schedulesProvider(bandId));
      ref.invalidate(dashboardProvider);
    } catch (_) {
      // Providers may be absent in tests; the local state is already correct.
    }
  }

  void _confirmCancel() {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: const Text('Cancel this rehearsal?'),
        message: const Text(
            'Everyone in the band will be notified. You can restore it later.'),
        actions: [
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.pop(sheetContext);
              _setCancelled(true);
            },
            child: const Text('Cancel Rehearsal'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetContext),
          child: const Text('Keep Rehearsal'),
        ),
      ),
    );
  }

  void _confirmRestore() {
    showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Restore this rehearsal?'),
        content: const Text('Everyone in the band will be notified.'),
        actions: [
          CupertinoDialogAction(
            child: const Text('Keep Cancelled'),
            onPressed: () => Navigator.pop(dialogContext),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            child: const Text('Restore'),
            onPressed: () {
              Navigator.pop(dialogContext);
              _setCancelled(false);
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rehearsal = _rehearsal;

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
            // "Plan this rehearsal" — upcoming, non-cancelled rehearsals only.
            if (!_editingNotes && _canPlan(rehearsal))
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () async {
                  final saved = await context.push<bool>(
                    '/rehearsals/${rehearsal.id}/planner',
                    extra: {
                      'rehearsalLabel': _formatDateShort(rehearsal.date),
                      'existingNotes': _notes,
                    },
                  );
                  if (saved == true) {
                    await _refreshNotes(rehearsal.id);
                  }
                },
                child: const Icon(CupertinoIcons.sparkles),
              ),
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
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (rehearsal.isCancelled) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: CupertinoColors.systemRed
                      .resolveFrom(context)
                      .withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: CupertinoColors.systemRed
                          .resolveFrom(context)
                          .withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(CupertinoIcons.xmark_circle,
                        color: CupertinoColors.systemRed.resolveFrom(context),
                        size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This rehearsal has been cancelled.',
                        style: TextStyle(
                          color: CupertinoColors.systemRed.resolveFrom(context),
                          fontWeight: FontWeight.w500,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 0),
                      onPressed: _togglingCancelled ? null : _confirmRestore,
                      child: _togglingCancelled
                          ? const CupertinoActivityIndicator()
                          : const Text('Restore',
                              style: TextStyle(fontSize: 15)),
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
                  color: CupertinoColors.tertiarySystemBackground
                      .resolveFrom(context),
                  borderRadius: BorderRadius.circular(8),
                ),
              )
            else if (_notes != null && _notes!.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: CupertinoColors.tertiarySystemBackground
                      .resolveFrom(context),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_notes!, style: const TextStyle(fontSize: 15)),
              )
            else
              Text(
                'No notes yet. Tap the edit button to add some.',
                style: TextStyle(fontSize: 13, color: context.secondaryText),
              ),
            const SizedBox(height: 20),
            const Text('Schedule',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: CupertinoColors.tertiarySystemBackground
                    .resolveFrom(context),
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
                      style:
                          TextStyle(fontSize: 13, color: context.secondaryText),
                    ),
                  ],
                ],
              ),
            ),
            if (rehearsal.associatedBookings.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text('Associated Bookings',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              ...rehearsal.associatedBookings
                  .map((b) => _AssociatedBookingRow(booking: b)),
            ],
            if (!rehearsal.isCancelled && _isUpcoming(rehearsal)) ...[
              const SizedBox(height: 24),
              CupertinoButton(
                onPressed: _togglingCancelled ? null : _confirmCancel,
                child: _togglingCancelled
                    ? const CupertinoActivityIndicator()
                    : Text(
                        'Cancel Rehearsal',
                        style: TextStyle(
                          color: CupertinoColors.systemRed.resolveFrom(context),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
              ),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  /// The AI planner is offered only for upcoming, non-cancelled rehearsals —
  /// you plan ahead for what to work on at one that hasn't happened yet.
  bool _canPlan(RehearsalDetail rehearsal) {
    if (rehearsal.isCancelled) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = rehearsal.parsedDate;
    final rehearsalDay = DateTime(d.year, d.month, d.day);
    return !rehearsalDay.isBefore(today);
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
        Icon(icon, size: 20, color: context.secondaryText),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(fontSize: 12, color: context.secondaryText)),
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
          Icon(CupertinoIcons.book, size: 20, color: context.secondaryText),
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
                  style: TextStyle(fontSize: 13, color: context.secondaryText),
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
