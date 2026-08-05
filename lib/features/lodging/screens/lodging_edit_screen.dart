import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tts_bandmate/core/network/geocoding.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';
import 'package:tts_bandmate/features/bookings/data/bookings_repository.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_summary.dart';
import 'package:tts_bandmate/features/bookings/providers/bookings_provider.dart';
import 'package:tts_bandmate/features/events/providers/events_provider.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';
import 'package:tts_bandmate/shared/widgets/address_autocomplete_field.dart';
import 'package:tts_bandmate/shared/widgets/error_view.dart';

import '../data/lodging_repository.dart';
import '../data/models/lodging.dart';
import '../providers/lodging_provider.dart';

/// A single option in the booking/event picker sheets. `id == null`
/// represents "None".
class _PickerOption {
  const _PickerOption(this.id, this.label);
  final int? id;
  final String label;
}

/// Mutable draft for a room row being edited. `id == null` means the room
/// will be inserted on save; a non-null `id` means it's an existing room
/// being updated (or, if dropped from the list, deleted).
class _RoomDraft {
  _RoomDraft({
    this.id,
    String label = '',
    String confirmation = '',
    String notes = '',
  })  : label = TextEditingController(text: label),
        confirmation = TextEditingController(text: confirmation),
        notes = TextEditingController(text: notes);

  final int? id;
  final TextEditingController label;
  final TextEditingController confirmation;
  final TextEditingController notes;

  void dispose() {
    label.dispose();
    confirmation.dispose();
    notes.dispose();
  }
}

class LodgingEditScreen extends ConsumerStatefulWidget {
  const LodgingEditScreen({super.key, required this.lodgingId});

  /// Null when creating a new lodging entry; the lodging's id when editing.
  final int? lodgingId;

  @override
  ConsumerState<LodgingEditScreen> createState() => _LodgingEditScreenState();
}

class _LodgingEditScreenState extends ConsumerState<LodgingEditScreen> {
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _notesController = TextEditingController();

  DateTime? _checkIn;
  DateTime? _checkOut;
  double? _lat;
  double? _lng;

  final List<_RoomDraft> _rooms = [];

  int? _bookingId;
  int? _eventId;

  bool _loading = true;
  bool _saving = false;
  bool _deleting = false;
  Object? _loadError;

  List<BookingSummary> _bookings = [];

  bool get _isEditing => widget.lodgingId != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _notesController.dispose();
    for (final r in _rooms) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      // Awaits rather than reading .value synchronously: by the time this
      // screen is reachable the router guard has already picked a band, but
      // the provider may still be resolving its persisted value from
      // storage on first read.
      final bandId = await ref.read(selectedBandProvider.future);
      if (bandId == null) throw StateError('No band selected');

      // Bookings (with their nested events) double as the source for both
      // the booking picker and the event picker — one lightweight fetch
      // instead of two separate list endpoints.
      final bookingsRepo = ref.read(bookingsRepositoryProvider);
      final bookings = await bookingsRepo.getBandBookings(bandId);

      if (_isEditing) {
        final detail =
            await ref.read(lodgingDetailProvider(widget.lodgingId!).future);
        final lodging = detail.lodging;
        _nameController.text = lodging.name;
        _addressController.text = lodging.address ?? '';
        _notesController.text = lodging.notes ?? '';
        _lat = lodging.latitude;
        _lng = lodging.longitude;
        _checkIn = lodging.parsedCheckIn;
        _checkOut = lodging.parsedCheckOut;
        _bookingId = lodging.booking?.id;
        _eventId = lodging.event?.id;
        _rooms.addAll(lodging.rooms.map((r) => _RoomDraft(
              id: r.id,
              label: r.label,
              confirmation: r.confirmationNumber ?? '',
              notes: r.notes ?? '',
            )));
      } else {
        final now = DateTime.now();
        _checkIn = DateTime(now.year, now.month, now.day, 15);
        _checkOut = _checkIn!.add(const Duration(days: 1)).copyWith(
              hour: 11,
              minute: 0,
              second: 0,
            );
      }

      if (!mounted) return;
      setState(() {
        _bookings = bookings;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _loading = false;
      });
    }
  }

  // ── Date pickers ─────────────────────────────────────────────────────────

  Future<void> _pickDateTime({required bool isCheckIn}) async {
    DateTime picked = (isCheckIn ? _checkIn : _checkOut) ??
        (isCheckIn
            ? DateTime.now()
            : (_checkIn ?? DateTime.now()).add(const Duration(hours: 20)));

    await showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => Container(
        height: 320,
        color: CupertinoColors.systemBackground.resolveFrom(sheetContext),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                CupertinoButton(
                  onPressed: () {
                    setState(() {
                      if (isCheckIn) {
                        _checkIn = null;
                      } else {
                        _checkOut = null;
                      }
                    });
                    Navigator.pop(sheetContext);
                  },
                  child: const Text('Clear'),
                ),
                CupertinoButton(
                  onPressed: () {
                    setState(() {
                      if (isCheckIn) {
                        _checkIn = picked;
                      } else {
                        _checkOut = picked;
                      }
                    });
                    Navigator.pop(sheetContext);
                  },
                  child: const Text('Done'),
                ),
              ],
            ),
            Expanded(
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.dateAndTime,
                initialDateTime: picked,
                onDateTimeChanged: (dt) => picked = dt,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Booking / event pickers ──────────────────────────────────────────────

  List<_PickerOption> get _bookingOptions => [
        const _PickerOption(null, 'None'),
        for (final b in _bookings) _PickerOption(b.id, b.name),
      ];

  List<_PickerOption> get _eventOptions {
    final dateFmt = DateFormat('MMM d, yyyy');
    final options = <_PickerOption>[const _PickerOption(null, 'None')];
    for (final b in _bookings) {
      for (final e in b.events) {
        final id = e.id;
        if (id == null) continue;
        final label = e.date.isEmpty
            ? e.title
            : '${e.title} · ${dateFmt.format(e.parsedDate)}';
        options.add(_PickerOption(id, label));
      }
    }
    return options;
  }

  Future<void> _pickBooking() => _showOptionPicker(
        title: 'Booking',
        options: _bookingOptions,
        selectedId: _bookingId,
        onSelected: (id) => setState(() => _bookingId = id),
      );

  Future<void> _pickEvent() => _showOptionPicker(
        title: 'Event',
        options: _eventOptions,
        selectedId: _eventId,
        onSelected: (id) => setState(() => _eventId = id),
      );

  Future<void> _showOptionPicker({
    required String title,
    required List<_PickerOption> options,
    required int? selectedId,
    required ValueChanged<int?> onSelected,
  }) async {
    final container = ProviderScope.containerOf(context);
    int index = options.indexWhere((o) => o.id == selectedId);
    if (index < 0) index = 0;

    await showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => UncontrolledProviderScope(
        container: container,
        child: Container(
          height: 300,
          color: CupertinoColors.systemBackground.resolveFrom(sheetContext),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Text(title,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  CupertinoButton(
                    onPressed: () {
                      onSelected(options[index].id);
                      Navigator.of(sheetContext).pop();
                    },
                    child: const Text('Done'),
                  ),
                ],
              ),
              Expanded(
                child: CupertinoPicker(
                  scrollController:
                      FixedExtentScrollController(initialItem: index),
                  itemExtent: 40,
                  onSelectedItemChanged: (i) => index = i,
                  children: options
                      .map((o) => Center(
                            child: Text(o.label,
                                style: const TextStyle(fontSize: 16),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Rooms ────────────────────────────────────────────────────────────────

  void _addRoom() {
    setState(() => _rooms.add(_RoomDraft()));
  }

  void _removeRoom(int index) {
    setState(() {
      final removed = _rooms.removeAt(index);
      removed.dispose();
    });
  }

  // ── Save / delete ────────────────────────────────────────────────────────

  bool get _datesValid =>
      _checkIn != null && _checkOut != null && _checkOut!.isAfter(_checkIn!);

  Future<void> _save() async {
    if (!_datesValid) return;

    setState(() => _saving = true);
    try {
      final repo = ref.read(lodgingRepositoryProvider);
      final bandId = ref.read(selectedBandProvider).value!;

      // Resolve lat/lng from the composed address if we don't already have
      // coordinates for it (e.g. user typed/edited the address by hand
      // without going through the autocomplete dropdown). Non-fatal.
      final address = _addressController.text.trim();
      if (address.isNotEmpty && _lat == null) {
        final point = await geocodeAddress(address);
        if (point != null) {
          _lat = point.latitude;
          _lng = point.longitude;
        }
      }

      final rooms = _rooms
          .where((r) => r.label.text.trim().isNotEmpty)
          .map((r) => LodgingRoom(
                id: r.id,
                label: r.label.text.trim(),
                confirmationNumber: r.confirmation.text.trim().isEmpty
                    ? null
                    : r.confirmation.text.trim(),
                notes:
                    r.notes.text.trim().isEmpty ? null : r.notes.text.trim(),
              ))
          .toList();

      if (!_isEditing) {
        final created = await repo.createLodging(
          bandId,
          name: _nameController.text.trim(),
          address: address.isEmpty ? null : address,
          latitude: _lat,
          longitude: _lng,
          checkInAt: _wire(_checkIn!),
          checkOutAt: _wire(_checkOut!),
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
          bookingId: _bookingId,
          eventId: _eventId,
          rooms: rooms,
        );
        _invalidate(bandId, created.id);
        if (mounted) context.pushReplacement('/lodging/${created.id}');
      } else {
        await repo.updateLodging(bandId, widget.lodgingId!, {
          'name': _nameController.text.trim(),
          'address': address.isEmpty ? null : address,
          'latitude': _lat,
          'longitude': _lng,
          'check_in_at': _wire(_checkIn!),
          'check_out_at': _wire(_checkOut!),
          'notes': _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
          'booking_id': _bookingId,
          'event_id': _eventId,
          'rooms': rooms.map((r) => r.toJson()).toList(),
        });
        _invalidate(bandId, widget.lodgingId!);
        if (mounted) context.pop();
      }
    } catch (e) {
      if (mounted) {
        showCupertinoDialog<void>(
          context: context,
          builder: (dialogContext) => CupertinoAlertDialog(
            title: const Text('Save Failed'),
            content: Text(ErrorView.friendlyMessage(e)),
            actions: [
              CupertinoDialogAction(
                isDefaultAction: true,
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Delete Lodging'),
        content: const Text(
            'This will permanently remove this lodging entry, its rooms, and its attachments.'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      final bandId = ref.read(selectedBandProvider).value!;
      final repo = ref.read(lodgingRepositoryProvider);
      await repo.deleteLodging(bandId, widget.lodgingId!);
      try {
        ref.read(lodgingsProvider(bandId).notifier).remove(widget.lodgingId!);
      } catch (_) {}
      // Same full invalidation set as save: without this, a booking/event
      // detail screen that already loaded this lodging keeps showing its
      // (now-deleted) card until the app is restarted or another edit
      // happens to invalidate it.
      _invalidate(bandId, widget.lodgingId!);
      if (mounted) {
        // /lodging routes live outside the ShellRoute (no bottom nav), so
        // context.go('/lodging') would collapse the whole navigation stack
        // and strand the user without a way back. Pop twice instead: once
        // to close this edit screen, once to close the detail screen
        // beneath it, landing on the list with its normal stack intact.
        context.pop();
        if (context.canPop()) context.pop();
      }
    } catch (e) {
      if (mounted) {
        showCupertinoDialog<void>(
          context: context,
          builder: (dialogContext) => CupertinoAlertDialog(
            title: const Text('Delete Failed'),
            content: Text(ErrorView.friendlyMessage(e)),
            actions: [
              CupertinoDialogAction(
                isDefaultAction: true,
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  String _wire(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:00';

  /// Refresh every surface that renders this lodging. Guarded: cache
  /// invalidation must never break the save/delete UX.
  void _invalidate(int bandId, int lodgingId) {
    try {
      ref.invalidate(lodgingsProvider(bandId));
      ref.invalidate(lodgingDetailProvider(lodgingId));
      // Event/booking detail payloads embed their lodgings — refresh those
      // families too so their lodging cards don't go stale after a save.
      ref.invalidate(bookingDetailProvider);
      ref.invalidate(eventDetailProvider);
    } catch (_) {}
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final title = _isEditing ? 'Edit Lodging' : 'New Lodging';

    if (_loading) {
      return CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(middle: Text(title)),
        child: const Center(child: CupertinoActivityIndicator()),
      );
    }

    if (_loadError != null) {
      return CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(middle: Text(title)),
        child: ErrorView(
          message: ErrorView.friendlyMessage(_loadError!),
          onRetry: () {
            setState(() {
              _loading = true;
              _loadError = null;
            });
            _load();
          },
        ),
      );
    }

    final dateFmt = DateFormat('EEE, MMM d, yyyy');
    final timeFmt = DateFormat('h:mm a');
    final bookingLabel =
        _bookingOptions.firstWhere((o) => o.id == _bookingId,
                orElse: () => const _PickerOption(null, 'None'))
            .label;
    final eventLabel = _eventOptions
        .firstWhere((o) => o.id == _eventId,
            orElse: () => const _PickerOption(null, 'None'))
        .label;

    final canSave = _nameController.text.trim().isNotEmpty &&
        _datesValid &&
        !_saving &&
        !_deleting;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(title),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: canSave ? _save : null,
          child: _saving
              ? const CupertinoActivityIndicator()
              : const Text('Save'),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const _SectionLabel('Name'),
            const SizedBox(height: 8),
            CupertinoTextField(
              controller: _nameController,
              placeholder: 'Hotel or lodging name',
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),

            AddressAutocompleteField(
              label: 'Address',
              controller: _addressController,
              onResolved: (components) {
                setState(() {
                  // Address text has already been narrowed to the street by
                  // the field; compose the full address and persist it —
                  // the controller's text is what gets saved, so it must
                  // carry city/state/zip, not just the street.
                  final full = [
                    _addressController.text,
                    components.city,
                    components.stateShort,
                    components.zip,
                  ].where((s) => s.trim().isNotEmpty).join(', ');
                  if (full.isNotEmpty) {
                    _addressController.text = full;
                  }
                  _lat = null;
                  _lng = null;
                  if (full.isNotEmpty) {
                    geocodeAddress(full).then((point) {
                      if (!mounted || point == null) return;
                      setState(() {
                        _lat = point.latitude;
                        _lng = point.longitude;
                      });
                    });
                  }
                });
              },
              onChanged: (_) => setState(() {
                _lat = null;
                _lng = null;
              }),
            ),
            const SizedBox(height: 8),

            const _SectionLabel('Dates'),
            const SizedBox(height: 8),
            _Card(
              child: Column(
                children: [
                  _DateRow(
                    label: 'Check-in',
                    value: _checkIn == null
                        ? 'Set date & time'
                        : '${dateFmt.format(_checkIn!)} · ${timeFmt.format(_checkIn!)}',
                    onTap: () => _pickDateTime(isCheckIn: true),
                  ),
                  Container(
                    height: 0.5,
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    color: CupertinoColors.separator.resolveFrom(context),
                  ),
                  _DateRow(
                    label: 'Check-out',
                    value: _checkOut == null
                        ? 'Set date & time'
                        : '${dateFmt.format(_checkOut!)} · ${timeFmt.format(_checkOut!)}',
                    onTap: () => _pickDateTime(isCheckIn: false),
                  ),
                ],
              ),
            ),
            if (!_datesValid && _checkIn != null && _checkOut != null) ...[
              const SizedBox(height: 6),
              const Text(
                'Check-out must be after check-in.',
                style: TextStyle(
                    fontSize: 12, color: CupertinoColors.destructiveRed),
              ),
            ],
            const SizedBox(height: 16),

            const _SectionLabel('Rooms'),
            const SizedBox(height: 8),
            for (int i = 0; i < _rooms.length; i++) ...[
              _RoomCard(
                draft: _rooms[i],
                onRemove: () => _removeRoom(i),
              ),
              const SizedBox(height: 8),
            ],
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _addRoom,
              child: const Text('Add room'),
            ),
            const SizedBox(height: 16),

            const _SectionLabel('Linked to'),
            const SizedBox(height: 8),
            _Card(
              child: Column(
                children: [
                  _PickerRow(
                    label: 'Booking',
                    value: bookingLabel,
                    onTap: _pickBooking,
                  ),
                  Container(
                    height: 0.5,
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    color: CupertinoColors.separator.resolveFrom(context),
                  ),
                  _PickerRow(
                    label: 'Event',
                    value: eventLabel,
                    onTap: _pickEvent,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            const _SectionLabel('Notes'),
            const SizedBox(height: 8),
            CupertinoTextField(
              controller: _notesController,
              placeholder: 'Optional notes',
              maxLines: 5,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),

            if (_isEditing) ...[
              const SizedBox(height: 32),
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _deleting ? null : _delete,
                child: _deleting
                    ? const CupertinoActivityIndicator()
                    : const Text(
                        'Delete Lodging',
                        style: TextStyle(color: CupertinoColors.destructiveRed),
                      ),
              ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ── Small presentational widgets ────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: context.secondaryText,
      ),
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

class _DateRow extends StatelessWidget {
  const _DateRow(
      {required this.label, required this.value, required this.onTap});
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(CupertinoIcons.calendar, size: 20, color: context.secondaryText),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 12, color: context.secondaryText),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(fontSize: 15, color: context.primaryText),
                ),
              ],
            ),
          ),
          Icon(CupertinoIcons.chevron_right,
              size: 16, color: context.tertiaryText),
        ],
      ),
    );
  }
}

class _PickerRow extends StatelessWidget {
  const _PickerRow(
      {required this.label, required this.value, required this.onTap});
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(label,
                style: TextStyle(fontSize: 15, color: context.primaryText)),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 15, color: context.secondaryText),
            ),
          ),
          const SizedBox(width: 6),
          Icon(CupertinoIcons.chevron_right,
              size: 14, color: context.tertiaryText),
        ],
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  const _RoomCard({required this.draft, required this.onRemove});
  final _RoomDraft draft;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: CupertinoTextField(
                  controller: draft.label,
                  placeholder: 'Room label (e.g. Room 214)',
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              CupertinoButton(
                padding: const EdgeInsets.only(left: 8),
                minimumSize: Size.zero,
                onPressed: onRemove,
                child: const Icon(CupertinoIcons.minus_circle,
                    size: 22, color: CupertinoColors.destructiveRed),
              ),
            ],
          ),
          const SizedBox(height: 8),
          CupertinoTextField(
            controller: draft.confirmation,
            placeholder: 'Confirmation number (optional)',
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          const SizedBox(height: 8),
          CupertinoTextField(
            controller: draft.notes,
            placeholder: 'Notes (optional)',
            maxLines: 3,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ],
      ),
    );
  }
}
