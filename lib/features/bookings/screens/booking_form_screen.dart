import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:dio/dio.dart';
import '../data/bookings_repository.dart';
import '../data/models/booking_detail.dart';
import '../data/models/deposit.dart';
import '../data/models/event_draft.dart';
import '../data/models/event_type.dart';
import '../providers/bookings_provider.dart';
import '../services/booking_save_orchestrator.dart';
import '../widgets/booking_form_navigation_guard.dart';
import '../widgets/booking_form_partial_failure_banner.dart';
import '../widgets/booking_save_button.dart';
import '../widgets/event_sub_form_card.dart';
import '../../events/data/events_repository.dart';
import '../../events/data/models/event_summary.dart';
import 'package:tts_bandmate/shared/cache/cache_invalidator.dart';

/// Formats a numeric text field as a USD currency value (e.g. "$1,234.56").
/// Digits are entered right-to-left like a cash register.
class _CurrencyInputFormatter extends TextInputFormatter {
  static final _fmt = NumberFormat.currency(symbol: r'$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Strip everything except digits.
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(text: '');
    }
    final cents = int.parse(digits);
    final formatted = _fmt.format(cents / 100);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  /// Parse a formatted string back to a plain decimal string for the API.
  static String? toDecimal(String formatted) {
    final digits = formatted.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;
    final cents = int.parse(digits);
    return (cents / 100).toStringAsFixed(2);
  }
}

// ── Per-row wrapper for the event sub-form list ───────────────────────────────

class _EventFormRow {
  _EventFormRow({
    this.id,
    this.key,
    required this.draft,
    this.localKey,
  });

  /// Set for existing events; null for newly-added rows.
  final int? id;

  /// Event UUID key (server-assigned). Set for existing events; null for new.
  final String? key;

  /// Local string key for new rows so the UI can map per-op failures back.
  final String? localKey;

  EventDraft draft;
}

// ─────────────────────────────────────────────────────────────────────────────

class BookingFormScreen extends ConsumerStatefulWidget {
  const BookingFormScreen({
    super.key,
    required this.bandId,
    this.existing,
  });

  final int bandId;
  final BookingDetail? existing;

  @override
  ConsumerState<BookingFormScreen> createState() => _BookingFormScreenState();
}

class _BookingFormScreenState extends ConsumerState<BookingFormScreen> {
  // ── Booking-level controllers ─────────────────────────────────────────────
  late final TextEditingController _name;
  late final TextEditingController _price;
  final FocusNode _priceFocus = FocusNode();
  late final TextEditingController _notes;
  late final TextEditingController _depositValue;
  final FocusNode _depositValueFocus = FocusNode();
  DepositType _depositType = DepositType.percent;

  int? _eventTypeId;
  String _contractOption = 'default';
  String? _status;

  // ── Create-mode toggles (both default ON so the default experience is unchanged)
  bool _depositEnabled = true;
  bool _contractEnabled = true;

  // ── Multi-event state ─────────────────────────────────────────────────────
  List<_EventFormRow> _eventRows = [];
  final Set<int> _deletedEventIds = {};
  BookingSaveResult? _lastSaveResult;
  int _localKeyCounter = 0;
  BookingDetail? _originalBooking;

  // ── Save state ────────────────────────────────────────────────────────────
  bool _saving = false;
  String? _createError;

  String _nextLocalKey() => 'new-${++_localKeyCounter}';

  bool get _isEdit => widget.existing != null;

  /// True when the contract is signed — deposit fields become read-only.
  bool get _isContractSigned =>
      widget.existing?.contract?.status == 'completed';

  bool get _priceIsZeroOrEmpty {
    final p = double.tryParse(
          _price.text.replaceAll(RegExp(r'[^0-9.]'), ''),
        ) ??
        0;
    return p <= 0;
  }

  String _depositCaption() {
    if (_isContractSigned) return 'Locked — contract is signed.';
    if (_depositType == DepositType.percent && _priceIsZeroOrEmpty) {
      return 'Enter a price above to use percent.';
    }
    final value = double.tryParse(_depositValue.text) ?? 0;
    // Parse price from the currency-formatted string (strip non-numeric except dot).
    final priceStr = _CurrencyInputFormatter.toDecimal(_price.text.trim()) ?? '0';
    final price = double.tryParse(priceStr) ?? 0;
    if (price <= 0) return '';
    if (_depositType == DepositType.percent) {
      if (value > 100) return 'Percent must be between 0 and 100.';
      return '= \$${(price * value / 100).toStringAsFixed(2)}';
    } else {
      if (value > price) return 'Deposit cannot exceed the booking price.';
      if (value <= 0) return '';
      return '= ${(value / price * 100).toStringAsFixed(1)}%';
    }
  }

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    final rawPrice = e?.price ?? '';
    final initialPrice = rawPrice.isNotEmpty
        ? () {
            final cents = (double.tryParse(rawPrice) ?? 0) * 100;
            return NumberFormat.currency(symbol: r'$').format(cents.round() / 100);
          }()
        : '';
    _price = TextEditingController(text: initialPrice);
    _notes = TextEditingController(text: e?.notes ?? '');
    _depositType = (e?.depositType == 'amount') ? DepositType.amount : DepositType.percent;
    _depositValue = TextEditingController(text: e?.depositValue ?? '50.00');
    _eventTypeId = e?.eventTypeId;
    _contractOption = e?.contractOption ?? 'default';
    _status = e?.status;

    if (e != null) {
      _initEventRows(e);
    } else {
      // Create mode: start with one empty row.
      _eventRows = [
        _EventFormRow(
          localKey: _nextLocalKey(),
          draft: EventDraft(
            title: '',
            date: _todayIso(),
          ),
        ),
      ];
    }
  }

  void _initEventRows(BookingDetail booking) {
    _originalBooking = booking;
    _eventRows = booking.events.map((e) {
      return _EventFormRow(
        id: e.id,
        key: e.key,
        draft: EventDraft(
          title: e.title,
          date: e.date,
          startTime: e.startTime,
          endTime: e.endTime,
          venueName: e.venueName,
          venueAddress: e.venueAddress,
          price: e.price,
        ),
      );
    }).toList();
  }

  static String _todayIso() {
    final now = DateTime.now();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '${now.year}-$m-$d';
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _priceFocus.dispose();
    _notes.dispose();
    _depositValue.dispose();
    _depositValueFocus.dispose();
    super.dispose();
  }

  // ── Event-type picker ─────────────────────────────────────────────────────

  void _pickEventType(List<EventType> types) {
    int temp = types.indexWhere((t) => t.id == _eventTypeId);
    if (temp < 0) temp = 0;
    showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => _PickerSheet(
        child: CupertinoPicker(
          scrollController: FixedExtentScrollController(initialItem: temp),
          itemExtent: 40,
          onSelectedItemChanged: (i) => temp = i,
          children: types
              .map((t) =>
                  Center(child: Text(t.name, style: const TextStyle(fontSize: 16))))
              .toList(),
        ),
        onDone: () =>
            setState(() => _eventTypeId = types.isEmpty ? null : types[temp].id),
      ),
    );
  }

  // ── Status picker ────────────────────────────────────────────────────────

  static const _statusOptions = ['pending', 'confirmed', 'cancelled', 'completed'];

  Future<void> _pickStatus(BuildContext context) async {
    final picked = await showCupertinoModalPopup<String>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Booking Status'),
        actions: _statusOptions
            .map((s) => CupertinoActionSheetAction(
                  onPressed: () => Navigator.of(ctx).pop(s),
                  child: Text(
                    s[0].toUpperCase() + s.substring(1),
                  ),
                ))
            .toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (picked != null) {
      setState(() => _status = picked);
    }
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  String _extractErrorMessage(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map) {
        final errors = data['errors'];
        if (errors is Map && errors.isNotEmpty) {
          return errors.values
              .expand((v) => v is List ? v : [v])
              .join('\n');
        }
        final message = data['message'];
        if (message is String && message.isNotEmpty) return message;
      }
    }
    return 'Could not save booking.';
  }

  /// Called by the Save button and by per-row retry taps.
  Future<void> _onSavePressed() async {
    if (_saving) return;

    if (_isEdit) {
      await _saveEdit();
    } else {
      await _saveCreate();
    }
  }

  Future<void> _saveEdit() async {
    setState(() => _saving = true);

    final snapshot = _buildSnapshot();
    if (snapshot.isEmpty) {
      setState(() => _saving = false);
      if (mounted) Navigator.of(context).pop(true);
      return;
    }

    final orchestrator = BookingSaveOrchestrator(
      bookingsRepository: ref.read(bookingsRepositoryProvider),
      eventsRepository: ref.read(eventsRepositoryProvider),
    );
    final result = await orchestrator.save(
      bandId: widget.bandId,
      bookingId: widget.existing!.id,
      snapshot: snapshot,
    );

    if (!mounted) return;
    setState(() {
      _saving = false;
      _lastSaveResult = result;
    });

    if (result.allSucceeded) {
      ref.read(cacheInvalidatorProvider).onBookingEventsChanged(
          bandId: widget.bandId, bookingId: widget.existing!.id);
      if (mounted) Navigator.of(context).pop(true);
    }
  }

  Future<void> _saveCreate() async {
    final nameVal = _name.text.trim();
    if (nameVal.isEmpty) {
      setState(() => _createError = 'Booking name is required.');
      return;
    }
    if (_eventTypeId == null) {
      setState(() => _createError = 'Event type is required.');
      return;
    }
    if (_eventRows.isEmpty) {
      setState(() => _createError = 'At least one event is required.');
      return;
    }

    setState(() {
      _saving = true;
      _createError = null;
    });

    final drafts = _eventRows.map((r) => r.draft).toList();
    final priceDecimal = _CurrencyInputFormatter.toDecimal(_price.text.trim());

    // Resolve deposit fields: OFF → explicit $0 amount; ON → user's input.
    final String createDepositType;
    final String createDepositValue;
    if (_depositEnabled) {
      createDepositType =
          _depositType == DepositType.amount ? 'amount' : 'percent';
      createDepositValue = _depositValue.text.trim().isEmpty
          ? '0'
          : _depositValue.text.trim();
    } else {
      createDepositType = 'amount';
      createDepositValue = '0';
    }

    // Resolve contract option: OFF → 'none'; ON → segmented control value.
    final String createContractOption =
        _contractEnabled ? _contractOption : 'none';

    try {
      await ref.read(bookingsRepositoryProvider).createBooking(
        widget.bandId,
        name: nameVal,
        eventTypeId: _eventTypeId!,
        price: priceDecimal,
        contractOption: createContractOption,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        depositType: createDepositType,
        depositValue: createDepositValue,
        events: drafts,
      );
      ref.read(cacheInvalidatorProvider).onBookingChanged(
            bandId: widget.bandId,
            bookingId: null,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        final message = _extractErrorMessage(e);
        setState(() {
          _saving = false;
          _createError = message;
        });
        showCupertinoDialog<void>(
          context: context,
          builder: (_) => CupertinoAlertDialog(
            title: const Text('Error'),
            content: Text(message),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  // ── Diff / snapshot ───────────────────────────────────────────────────────

  BookingFormSnapshot _buildSnapshot() {
    final orig = _originalBooking;
    if (orig == null) return const BookingFormSnapshot();

    final nameVal = _name.text.trim();
    final priceDecimal = _CurrencyInputFormatter.toDecimal(_price.text.trim());
    final notesVal = _notes.text.trim();

    final newDepositType =
        _depositType == DepositType.amount ? 'amount' : 'percent';
    final newDepositValue = _depositValue.text.trim();

    final patch = BookingFieldDiff(
      name: nameVal != orig.name ? nameVal : null,
      eventTypeId: _eventTypeId != orig.eventTypeId ? _eventTypeId : null,
      price: priceDecimal != orig.price ? priceDecimal : null,
      status: _status != orig.status ? _status : null,
      contractOption:
          _contractOption != (orig.contractOption ?? 'default') ? _contractOption : null,
      notes: notesVal != (orig.notes ?? '') ? notesVal : null,
      depositType: newDepositType != orig.depositType ? newDepositType : null,
      depositValue: newDepositValue != orig.depositValue ? newDepositValue : null,
    );

    final eventUpdates = <String, EventDraft>{};
    final eventCreates = <String, EventDraft>{};

    for (final row in _eventRows) {
      if (row.id != null && row.key != null) {
        final original = orig.events.where((e) => e.id == row.id).firstOrNull;
        if (original != null && _eventDraftDiffersFromOriginal(row.draft, original)) {
          eventUpdates[row.key!] = row.draft;
        }
      } else if (row.localKey != null) {
        eventCreates[row.localKey!] = row.draft;
      }
    }

    return BookingFormSnapshot(
      bookingPatch: patch.isEmpty ? null : patch,
      eventUpdates: eventUpdates,
      eventCreates: eventCreates,
      eventDeletes: _deletedEventIds,
    );
  }

  bool _eventDraftDiffersFromOriginal(EventDraft draft, EventSummary original) {
    return draft.title != original.title ||
        draft.date != original.date ||
        draft.startTime != original.startTime ||
        draft.endTime != original.endTime ||
        draft.venueName != original.venueName ||
        draft.venueAddress != original.venueAddress ||
        draft.price != original.price;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final eventTypesAsync = ref.watch(eventTypesProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        final allow = await BookingFormNavigationGuard.shouldAllowLeave(
            context, _lastSaveResult);
        if (allow) {
          navigator.pop();
        }
      },
      child: CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          middle: Text(_isEdit ? 'Edit Booking' : 'New Booking'),
          trailing: BookingSaveButton(
            isSaving: _saving,
            lastResult: _lastSaveResult,
            onPressed: _onSavePressed,
          ),
        ),
        child: ListView(
          children: [
            // ── Partial failure banner ──────────────────────────────────────
            if (_lastSaveResult?.allFailed == true)
              BookingFormPartialFailureBanner(
                onDismiss: () => setState(() => _lastSaveResult = null),
              ),

            // ── Core details ────────────────────────────────────────────────
            CupertinoFormSection.insetGrouped(
              header: const Text('DETAILS'),
              children: [
                CupertinoTextFormFieldRow(
                  controller: _name,
                  prefix: const Text('Name'),
                  placeholder: 'Booking name',
                  textInputAction: TextInputAction.next,
                ),
                // Event type — tappable row
                eventTypesAsync.when(
                  loading: () => const CupertinoFormRow(
                    prefix: Text('Event Type'),
                    child: CupertinoActivityIndicator(),
                  ),
                  error: (_, __) => const CupertinoFormRow(
                    prefix: Text('Event Type'),
                    child: Text('—',
                        style: TextStyle(
                            color: CupertinoColors.secondaryLabel)),
                  ),
                  data: (types) {
                    final selected = types
                        .where((t) => t.id == _eventTypeId)
                        .firstOrNull;
                    return GestureDetector(
                      onTap: () => _pickEventType(types),
                      child: CupertinoFormRow(
                        prefix: const Text('Event Type'),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              selected?.name ?? 'Select',
                              style: TextStyle(
                                color: selected == null
                                    ? CupertinoColors.placeholderText
                                        .resolveFrom(context)
                                    : CupertinoColors.label.resolveFrom(context),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(CupertinoIcons.chevron_right,
                                size: 14,
                                color: CupertinoColors.tertiaryLabel
                                    .resolveFrom(context)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                // Status picker — edit mode only (create lets the backend default)
                if (_isEdit)
                  GestureDetector(
                    onTap: () => _pickStatus(context),
                    child: CupertinoFormRow(
                      prefix: const Text('Status'),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            _status != null
                                ? _status![0].toUpperCase() +
                                    _status!.substring(1)
                                : 'pending',
                            style: TextStyle(
                              color: CupertinoColors.label.resolveFrom(context),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(CupertinoIcons.chevron_right,
                              size: 14,
                              color: CupertinoColors.tertiaryLabel
                                  .resolveFrom(context)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),

            // ── Financial ───────────────────────────────────────────────────
            CupertinoFormSection.insetGrouped(
              header: const Text('FINANCIALS'),
              children: [
                CupertinoTextFormFieldRow(
                  controller: _price,
                  focusNode: _priceFocus,
                  textAlign: TextAlign.end,
                  prefix: const Text('Price'),
                  placeholder: r'$0.00',
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  onEditingComplete: () => _priceFocus.unfocus(),
                  inputFormatters: [_CurrencyInputFormatter()],
                  // Recompute the deposit caption whenever price changes.
                  onChanged: (_) => setState(() {}),
                ),
                // Deposit toggle — create mode only.
                if (!_isEdit)
                  CupertinoFormRow(
                    prefix: const Text('Deposit'),
                    child: CupertinoSwitch(
                      value: _depositEnabled,
                      onChanged: (v) => setState(() => _depositEnabled = v),
                    ),
                  ),
                // Deposit input + $/% control + caption — always in edit mode;
                // in create mode only when the deposit toggle is ON.
                if (_isEdit || _depositEnabled) ...[
                  CupertinoTextFormFieldRow(
                    controller: _depositValue,
                    focusNode: _depositValueFocus,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    enabled: !_isContractSigned &&
                        !(_depositType == DepositType.percent &&
                            _priceIsZeroOrEmpty),
                    // In create mode the toggle row owns the 'Deposit' label,
                    // so the input is just 'Amount'. In edit mode there is no
                    // toggle row, so keep the original 'Deposit' label.
                    prefix: Text(_isEdit ? 'Deposit' : 'Amount'),
                    placeholder:
                        _depositType == DepositType.percent ? '50' : '500.00',
                    onChanged: (_) => setState(() {}),
                  ),
                  // $/% toggle
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Semantics(
                            label: 'Deposit type: dollar amount or percent',
                            child: CupertinoSlidingSegmentedControl<DepositType>(
                              groupValue: _depositType,
                              onValueChanged: (DepositType? val) {
                                // No-op when contract is signed; otherwise switch mode.
                                if (_isContractSigned) return;
                                if (val == null || val == _depositType) return;
                                setState(() {
                                  _depositType = val;
                                  _depositValue.text = '';
                                });
                              },
                              children: const {
                                DepositType.amount: Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 12),
                                  child: Text('\$'),
                                ),
                                DepositType.percent: Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 12),
                                  child: Text('%'),
                                ),
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Live computed counterpart (e.g. "= $500.00" or "= 50.0%")
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      _depositCaption(),
                      style: TextStyle(
                        color: CupertinoColors.secondaryLabel.resolveFrom(context),
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ],
            ),

            // ── Events ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'EVENTS',
                      style: TextStyle(
                        fontSize: 13,
                        color: CupertinoColors.secondaryLabel.resolveFrom(context),
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  ..._eventRows.map((row) {
                    // Determine the failure-lookup key for this row.
                    // Updates are keyed by UUID (row.key); creates by localKey.
                    final keyForError = row.id != null
                        ? 'EVT-${row.key ?? row.id}'
                        : 'NEW-${row.localKey}';
                    String? err;
                    if (_lastSaveResult != null) {
                      for (final entry in _lastSaveResult!.failureKeys) {
                        if (entry.key == keyForError) {
                          err = entry.value.message;
                          break;
                        }
                      }
                    }
                    return EventSubFormCard(
                      key: ValueKey(row.id ?? row.localKey),
                      draft: row.draft,
                      canDelete: _eventRows.length > 1,
                      saveError: err,
                      onChange: (newDraft) {
                        setState(() => row.draft = newDraft);
                      },
                      onDelete: () {
                        setState(() {
                          if (row.id != null) _deletedEventIds.add(row.id!);
                          _eventRows.remove(row);
                        });
                      },
                      onRetryRow: _onSavePressed,
                    );
                  }),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    child: const Text('+ Add event'),
                    onPressed: () {
                      setState(() {
                        _eventRows.add(_EventFormRow(
                          localKey: _nextLocalKey(),
                          draft: EventDraft(
                            title: _eventRows.isNotEmpty
                                ? _name.text.trim()
                                : '',
                            date: _eventRows.isNotEmpty
                                ? _eventRows.last.draft.date
                                : _todayIso(),
                          ),
                        ));
                      });
                    },
                  ),
                ],
              ),
            ),

            // ── Contract option (create only) ────────────────────────────────
            if (!_isEdit)
              CupertinoFormSection.insetGrouped(
                header: const Text('CONTRACT'),
                children: [
                  // Toggle row: controls whether a contract is attached at all.
                  CupertinoFormRow(
                    prefix: const Text('Contract'),
                    child: CupertinoSwitch(
                      value: _contractEnabled,
                      onChanged: (v) => setState(() => _contractEnabled = v),
                    ),
                  ),
                  // Segmented control only shown when contract is enabled.
                  if (_contractEnabled)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      child: CupertinoSlidingSegmentedControl<String>(
                        groupValue: _contractOption,
                        onValueChanged: (v) {
                          if (v != null) setState(() => _contractOption = v);
                        },
                        children: const {
                          'default': Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Text('Default'),
                          ),
                          'none': Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Text('None'),
                          ),
                          'external': Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Text('External'),
                          ),
                        },
                      ),
                    ),
                ],
              ),

            // ── Notes ────────────────────────────────────────────────────────
            CupertinoFormSection.insetGrouped(
              header: const Text('NOTES'),
              children: [
                CupertinoTextFormFieldRow(
                  controller: _notes,
                  placeholder: 'Add notes...',
                  maxLines: 5,
                  textInputAction: TextInputAction.done,
                ),
              ],
            ),

            // ── Create-mode error ─────────────────────────────────────────────
            if (_createError != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  _createError!,
                  style: TextStyle(
                      color: CupertinoColors.systemRed.resolveFrom(context),
                      fontSize: 13),
                ),
              ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

// ── Reusable picker bottom sheet ─────────────────────────────────────────────

class _PickerSheet extends StatelessWidget {
  const _PickerSheet({required this.child, required this.onDone});

  final Widget child;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 300,
      color: CupertinoColors.systemBackground.resolveFrom(context),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              CupertinoButton(
                onPressed: () {
                  onDone();
                  Navigator.of(context).pop();
                },
                child: const Text('Done',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
