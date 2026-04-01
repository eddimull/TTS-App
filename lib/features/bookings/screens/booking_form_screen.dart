import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dio/dio.dart';
import '../data/bookings_repository.dart';
import '../data/models/booking_date_status.dart';
import '../data/models/booking_detail.dart';
import '../data/models/event_type.dart';
import '../data/venue_search_service.dart';
import '../providers/bookings_provider.dart';
import '../widgets/booking_calendar_picker.dart';
import 'package:tts_bandmate/core/config/app_config.dart';

// Whether the current platform supports google_maps_flutter.
bool get _mapsSupported => kIsWeb || Platform.isAndroid || Platform.isIOS;

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
  late final TextEditingController _name;
  late final TextEditingController _price;
  final FocusNode _priceFocus = FocusNode();
  late final TextEditingController _venueName;
  late final TextEditingController _venueAddress;
  late final TextEditingController _notes;

  // Coordinates for the selected venue — drive the live map preview.
  double? _venueLat;
  double? _venueLng;

  late DateTime _date;
  DateTime? _startTime;
  int _durationIndex = 2; // defaults to "1 hr"
  int? _eventTypeId;
  String _contractOption = 'default';

  bool _saving = false;
  String? _error;

  static const _durations = [
    '0.5 hr', '1 hr', '1.5 hr', '2 hr', '2.5 hr', '3 hr',
    '3.5 hr', '4 hr', '4.5 hr', '5 hr', '5.5 hr', '6 hr',
    '6.5 hr', '7 hr', '7.5 hr', '8 hr',
  ];

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
    _venueName = TextEditingController(text: e?.venueName ?? '');
    _venueAddress = TextEditingController(text: e?.venueAddress ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');
    _date = e?.parsedDate ?? DateTime.now();
    _eventTypeId = e?.eventTypeId;
    _contractOption = e?.contractOption ?? 'default';

    _venueAddress.addListener(() => setState(() {}));
    _venueName.addListener(() => setState(() {}));

    if (e?.startTime != null && e!.startTime!.isNotEmpty) {
      final parts = e.startTime!.split(':');
      if (parts.length >= 2) {
        final h = int.tryParse(parts[0]) ?? 0;
        final m = int.tryParse(parts[1]) ?? 0;
        _startTime = DateTime(2000, 1, 1, h, m);
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _priceFocus.dispose();
    _venueName.dispose();
    _venueAddress.dispose();
    _notes.dispose();
    super.dispose();
  }

  bool get _isEdit => widget.existing != null;

  String _formatDate(DateTime d) => DateFormat('EEEE, MMMM d, yyyy').format(d);

  String _formatTime(DateTime? t) {
    if (t == null) return 'Not set';
    return DateFormat('h:mm a').format(t);
  }

  // ── Pickers ───────────────────────────────────────────────────────────────

  void _pickDate() {
    // Snapshot the current cached value.  Because build() already watches
    // bookingDateInfoProvider, this is typically already resolved to data
    // by the time the user taps the Date row.
    final statusesAsync = ref.read(bookingDateInfoProvider(widget.bandId));

    showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => _DatePickerSheet(
        initialDate: _date,
        statusesAsync: statusesAsync,
        onDone: (picked) => setState(() => _date = picked),
      ),
    );
  }

  void _pickTime() {
    DateTime temp = _startTime ?? DateTime(2000, 1, 1, 19, 0);
    showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => _PickerSheet(
        child: CupertinoDatePicker(
          mode: CupertinoDatePickerMode.time,
          initialDateTime: temp,
          use24hFormat: false,
          onDateTimeChanged: (t) => temp = t,
        ),
        onDone: () => setState(() => _startTime = temp),
      ),
    );
  }

  void _pickDuration() {
    int temp = _durationIndex;
    showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => _PickerSheet(
        child: CupertinoPicker(
          scrollController:
              FixedExtentScrollController(initialItem: _durationIndex),
          itemExtent: 40,
          onSelectedItemChanged: (i) => temp = i,
          children: _durations
              .map((d) => Center(child: Text(d, style: const TextStyle(fontSize: 16))))
              .toList(),
        ),
        onDone: () => setState(() => _durationIndex = temp),
      ),
    );
  }

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

  // ── Venue ─────────────────────────────────────────────────────────────────

  /// Step 1: open search sheet → get a VenuePrediction.
  /// Step 2: on platforms that support maps, geocode + open map picker.
  /// Step 3: map picker pops with final VenueDetails (name/address/lat/lng).
  ///
  /// If the user cancels the map picker they are looped back to the search
  /// sheet (with their previous query pre-populated) rather than dropped all
  /// the way back to the booking form.
  Future<void> _openVenueSearch() async {
    final service = ref.read(venueSearchServiceProvider);

    // Seed the search box with whatever venue name is already typed.
    String lastQuery = _venueName.text;

    while (true) {
      // Step 1 — search sheet returns a raw prediction.
      final prediction = await Navigator.of(context).push<VenuePrediction>(
        CupertinoPageRoute(
          builder: (_) => _VenueSearchSheet(
            initialText: lastQuery,
            service: service,
          ),
        ),
      );
      if (prediction == null || !mounted) return; // user cancelled search entirely

      if (!_mapsSupported) {
        // Linux: no map available — just accept name + address from autocomplete.
        setState(() {
          _venueName.text = prediction.name;
          _venueAddress.text = prediction.address;
          _venueLat = null;
          _venueLng = null;
        });
        return;
      }

      // Persist the query so that if we loop back the field is pre-populated.
      lastQuery = prediction.name;

      // Step 2 — geocode the address so the map picker has a starting position.
      LatLng? initialPosition;
      if (AppConfig.googlePlacesApiKey.isNotEmpty) {
        initialPosition = await _geocodeAddress(prediction.address);
      }

      if (!mounted) return;

      // Step 3 — full-screen map picker with draggable marker.
      // Returns null when the user presses Cancel → loop back to search.
      final details = await Navigator.of(context).push<VenueDetails>(
        CupertinoPageRoute(
          builder: (_) => _VenueMapPickerScreen(
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

      setState(() {
        _venueName.text = details.name;
        _venueAddress.text = details.address;
        _venueLat = details.lat;
        _venueLng = details.lng;
      });
      return;
    }
  }

  void _clearVenue() {
    setState(() {
      _venueName.text = '';
      _venueAddress.text = '';
      _venueLat = null;
      _venueLng = null;
    });
  }

  Future<void> _openInMaps() async {
    final address = _venueAddress.text.trim();
    if (address.isEmpty) return;
    final Uri uri;
    if (_venueLat != null && _venueLng != null) {
      uri = Uri.parse(
          'https://maps.google.com/?q=$_venueLat,$_venueLng');
    } else {
      uri = Uri.parse(
          'https://maps.google.com/?q=${Uri.encodeComponent(address)}');
    }
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
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

  Future<void> _save() async {
    final nameVal = _name.text.trim();
    if (nameVal.isEmpty) {
      setState(() => _error = 'Booking name is required.');
      return;
    }
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    final dateStr =
        '${_date.year.toString().padLeft(4, '0')}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';

    String? startTimeStr;
    if (_startTime != null) {
      startTimeStr =
          '${_startTime!.hour.toString().padLeft(2, '0')}:${_startTime!.minute.toString().padLeft(2, '0')}';
    }

    final body = <String, dynamic>{
      'name': nameVal,
      'date': dateStr,
      'venue_name': _venueName.text.trim(),
      'venue_address': _venueAddress.text.trim(),
      'notes': _notes.text.trim(),
      'price': _CurrencyInputFormatter.toDecimal(_price.text.trim()),
      if (_eventTypeId != null) 'event_type_id': _eventTypeId,
      if (startTimeStr != null) 'start_time': startTimeStr,
      'duration': (_durationIndex + 1) * 0.5,
    };

    // Contract option only applies on create.
    if (!_isEdit) body['contract_option'] = _contractOption;

    try {
      final repo = ref.read(bookingsRepositoryProvider);
      if (_isEdit) {
        await repo.updateBooking(
            widget.bandId, widget.existing!.id, body);
        ref.invalidate(bookingDetailProvider(
            (bandId: widget.bandId, bookingId: widget.existing!.id)));
      } else {
        await repo.createBooking(widget.bandId, body);
      }
      ref.invalidate(
          bandBookingsProvider(BandBookingsParams(bandId: widget.bandId)));
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        final message = _extractErrorMessage(e);
        setState(() {
          _saving = false;
          _error = message;
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

  @override
  Widget build(BuildContext context) {
    final eventTypesAsync = ref.watch(eventTypesProvider);
    // Pre-fetch booking date info so the calendar is ready before the user
    // taps the Date row.  We only watch, not render — the sheet reads the
    // cached AsyncValue via ref.read() when it opens.
    ref.watch(bookingDateInfoProvider(widget.bandId));
    final hasVenue = _venueName.text.isNotEmpty;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(_isEdit ? 'Edit Booking' : 'New Booking'),
        trailing: _saving
            ? const CupertinoActivityIndicator()
            : CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _save,
                child: const Text('Save',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
      ),
      child: ListView(
        children: [
          // ── Core details ───────────────────────────────────────────────
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
              // Date
              GestureDetector(
                onTap: _pickDate,
                child: CupertinoFormRow(
                  prefix: const Text('Date'),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(_formatDate(_date)),
                      const SizedBox(width: 4),
                      Icon(CupertinoIcons.chevron_right,
                          size: 14,
                          color: CupertinoColors.tertiaryLabel
                              .resolveFrom(context)),
                    ],
                  ),
                ),
              ),
              // Start time
              GestureDetector(
                onTap: _pickTime,
                child: CupertinoFormRow(
                  prefix: const Text('Start Time'),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        _formatTime(_startTime),
                        style: TextStyle(
                          color: _startTime == null
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
              ),
              // Duration
              GestureDetector(
                onTap: _pickDuration,
                child: CupertinoFormRow(
                  prefix: const Text('Duration'),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(_durations[_durationIndex]),
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

          // ── Financial ──────────────────────────────────────────────────
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
              ),
            ],
          ),

          // ── Venue ──────────────────────────────────────────────────────
          CupertinoFormSection.insetGrouped(
            header: const Text('VENUE'),
            children: [
              if (!hasVenue)
                // Empty state: single tappable row to open search.
                GestureDetector(
                  onTap: _openVenueSearch,
                  child: CupertinoFormRow(
                    prefix: const Text('Venue'),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          'Search venue',
                          style: TextStyle(
                            color: CupertinoColors.placeholderText
                                .resolveFrom(context),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(CupertinoIcons.search,
                            size: 16,
                            color: CupertinoColors.tertiaryLabel
                                .resolveFrom(context)),
                      ],
                    ),
                  ),
                )
              else
                // Selected state: live map preview card with venue info.
                _VenuePreviewCard(
                  venueName: _venueName.text,
                  venueAddress: _venueAddress.text,
                  lat: _venueLat,
                  lng: _venueLng,
                  onOpenMaps: _openInMaps,
                  onChange: _openVenueSearch,
                  onClear: _clearVenue,
                ),
            ],
          ),

          // ── Contract option (create only) ──────────────────────────────
          if (!_isEdit)
            CupertinoFormSection.insetGrouped(
              header: const Text('CONTRACT'),
              children: [
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

          // ── Notes ──────────────────────────────────────────────────────
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

          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                _error!,
                style: TextStyle(
                    color: CupertinoColors.systemRed.resolveFrom(context),
                    fontSize: 13),
              ),
            ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ── Geocoding helper ──────────────────────────────────────────────────────────

/// Returns the first result's coordinates from the Geocoding REST API, or null
/// if the request fails or returns no results.
Future<LatLng?> _geocodeAddress(String address) async {
  if (address.trim().isEmpty || AppConfig.googlePlacesApiKey.isEmpty) {
    return null;
  }
  try {
    final dio = Dio();
    final response = await dio.get<Map<String, dynamic>>(
      'https://maps.googleapis.com/maps/api/geocode/json',
      queryParameters: {
        'address': address,
        'key': AppConfig.googlePlacesApiKey,
      },
    );
    final results = response.data?['results'] as List<dynamic>?;
    if (results == null || results.isEmpty) return null;
    final location =
        (results.first as Map<String, dynamic>)['geometry']?['location']
            as Map<String, dynamic>?;
    if (location == null) return null;
    final lat = (location['lat'] as num?)?.toDouble();
    final lng = (location['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  } catch (_) {
    return null;
  }
}

// ── Venue preview card (shown in form after selection) ────────────────────────

class _VenuePreviewCard extends StatelessWidget {
  const _VenuePreviewCard({
    required this.venueName,
    required this.venueAddress,
    required this.lat,
    required this.lng,
    required this.onOpenMaps,
    required this.onChange,
    required this.onClear,
  });

  final String venueName;
  final String venueAddress;
  final double? lat;
  final double? lng;
  final VoidCallback onOpenMaps;
  final VoidCallback onChange;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Match the horizontal inset of CupertinoFormSection.insetGrouped rows.
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Live map thumbnail — only on platforms that support google_maps_flutter.
            if (_mapsSupported && lat != null && lng != null)
              _LiveMapThumbnail(lat: lat!, lng: lng!)
            else if (lat != null && lng != null)
              // Fallback for Linux when coords exist (shouldn't happen normally).
              _MapPinPlaceholder(),

            // Venue info + action row.
            Container(
              color: CupertinoColors.secondarySystemGroupedBackground
                  .resolveFrom(context),
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          venueName,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color:
                                CupertinoColors.label.resolveFrom(context),
                          ),
                        ),
                        if (venueAddress.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            venueAddress,
                            style: TextStyle(
                              fontSize: 13,
                              color: CupertinoColors.secondaryLabel
                                  .resolveFrom(context),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Action buttons: open in Maps, change, clear.
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Semantics(
                        label: 'Open venue in Maps',
                        child: CupertinoButton(
                          padding: const EdgeInsets.all(8),
                          onPressed: onOpenMaps,
                          child: Icon(
                            CupertinoIcons.map,
                            size: 20,
                            color: CupertinoColors.activeBlue
                                .resolveFrom(context),
                          ),
                        ),
                      ),
                      Semantics(
                        label: 'Change venue',
                        child: CupertinoButton(
                          padding: const EdgeInsets.all(8),
                          onPressed: onChange,
                          child: Icon(
                            CupertinoIcons.pencil,
                            size: 20,
                            color: CupertinoColors.activeBlue
                                .resolveFrom(context),
                          ),
                        ),
                      ),
                      Semantics(
                        label: 'Clear venue',
                        child: CupertinoButton(
                          padding: const EdgeInsets.all(8),
                          onPressed: onClear,
                          child: Icon(
                            CupertinoIcons.xmark_circle,
                            size: 20,
                            color: CupertinoColors.secondaryLabel
                                .resolveFrom(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Live map thumbnail (non-interactive GoogleMap in the preview card) ─────────

class _LiveMapThumbnail extends StatelessWidget {
  const _LiveMapThumbnail({required this.lat, required this.lng});

  final double lat;
  final double lng;

  @override
  Widget build(BuildContext context) {
    final position = LatLng(lat, lng);
    return SizedBox(
      height: 140,
      child: GoogleMap(
        initialCameraPosition: CameraPosition(target: position, zoom: 15),
        markers: {
          Marker(markerId: const MarkerId('venue'), position: position),
        },
        // Disable all gestures — this is a read-only thumbnail.
        zoomGesturesEnabled: false,
        scrollGesturesEnabled: false,
        tiltGesturesEnabled: false,
        rotateGesturesEnabled: false,
        zoomControlsEnabled: false,
        myLocationButtonEnabled: false,
        mapToolbarEnabled: false,
        // liteModeEnabled is Android-only; reduces GPU overhead for static views.
        liteModeEnabled: !kIsWeb && Platform.isAndroid,
      ),
    );
  }
}

// ── Map-pin icon placeholder (Linux / no coordinates) ─────────────────────────

class _MapPinPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 140,
      color: CupertinoColors.systemGrey5.resolveFrom(context),
      child: Center(
        child: Icon(
          CupertinoIcons.map_pin_ellipse,
          size: 36,
          color: CupertinoColors.tertiaryLabel.resolveFrom(context),
        ),
      ),
    );
  }
}

// ── Full-screen map picker ────────────────────────────────────────────────────
//
// Shown after a venue is selected in the search sheet. The user can drag the
// red marker to fine-tune the pin location. Tapping "Confirm Location" pops
// with the final VenueDetails including the marker's coordinates.

class _VenueMapPickerScreen extends StatefulWidget {
  const _VenueMapPickerScreen({
    required this.venueName,
    required this.venueAddress,
    required this.initialPosition,
  });

  final String venueName;
  final String venueAddress;

  /// Geocoded starting position. Null when geocoding failed — the map will
  /// open at a world-level zoom and the user can pan to the correct location.
  final LatLng? initialPosition;

  @override
  State<_VenueMapPickerScreen> createState() => _VenueMapPickerScreenState();
}

class _VenueMapPickerScreenState extends State<_VenueMapPickerScreen> {
  // Falls back to a central world position if geocoding returned nothing.
  static const _worldCenter = LatLng(20.0, 0.0);

  late LatLng _markerPosition;

  @override
  void initState() {
    super.initState();
    _markerPosition = widget.initialPosition ?? _worldCenter;
  }

  void _onMarkerDragEnd(LatLng position) {
    setState(() => _markerPosition = position);
  }

  void _confirm() {
    Navigator.of(context).pop(VenueDetails(
      name: widget.venueName,
      address: widget.venueAddress,
      lat: _markerPosition.latitude,
      lng: _markerPosition.longitude,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Confirm Location'),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ),
      child: Stack(
        children: [
          // Full-screen interactive map.
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _markerPosition,
                zoom: widget.initialPosition != null ? 15 : 2,
              ),
              onMapCreated: (_) {},
              markers: {
                Marker(
                  markerId: const MarkerId('venue'),
                  position: _markerPosition,
                  draggable: true,
                  onDragEnd: _onMarkerDragEnd,
                ),
              },
              zoomControlsEnabled: false,
              myLocationButtonEnabled: false,
              mapToolbarEnabled: false,
            ),
          ),

          // Venue name chip overlaid at the top of the map.
          Positioned(
            top: 8,
            left: 16,
            right: 16,
            child: _VenueNameChip(
              name: widget.venueName,
              address: widget.venueAddress,
            ),
          ),

          // "Confirm Location" button anchored at the bottom.
          Positioned(
            left: 16,
            right: 16,
            bottom: bottomPadding + 16,
            child: Semantics(
              label: 'Confirm venue location',
              child: CupertinoButton.filled(
                onPressed: _confirm,
                child: const Text(
                  'Confirm Location',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Venue name chip overlay on the map picker ─────────────────────────────────

class _VenueNameChip extends StatelessWidget {
  const _VenueNameChip({required this.name, required this.address});

  final String name;
  final String address;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground
            .resolveFrom(context)
            .withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x18000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            name,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: CupertinoColors.label.resolveFrom(context),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (address.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              address,
              style: TextStyle(
                fontSize: 13,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'Drag the marker to adjust the pin.',
            style: TextStyle(
              fontSize: 12,
              color: CupertinoColors.tertiaryLabel.resolveFrom(context),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Venue search sheet ────────────────────────────────────────────────────────
//
// Presents an autocomplete search field and a flat results list.
// Tapping a result immediately pops with the selected VenuePrediction —
// no intermediate map preview pane here; the map lives in its own screen.

class _VenueSearchSheet extends StatefulWidget {
  const _VenueSearchSheet({
    required this.initialText,
    required this.service,
  });

  final String initialText;
  final VenueSearchService service;

  @override
  State<_VenueSearchSheet> createState() => _VenueSearchSheetState();
}

class _VenueSearchSheetState extends State<_VenueSearchSheet> {
  late final TextEditingController _query;
  List<VenuePrediction> _predictions = [];
  bool _searching = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _query = TextEditingController(text: widget.initialText);
    _query.addListener(_onQueryChanged);
    if (widget.initialText.isNotEmpty) {
      _search();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _search);
  }

  Future<void> _search() async {
    if (!mounted) return;
    setState(() => _searching = true);
    final results = await widget.service.search(_query.text);
    if (!mounted) return;
    setState(() {
      _predictions = results;
      _searching = false;
    });
  }

  /// Single tap confirms immediately — map picking happens back in the form.
  void _select(VenuePrediction prediction) {
    Navigator.of(context).pop(prediction);
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Select Venue'),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ),
      child: Column(
        children: [
          // Search bar.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: CupertinoSearchTextField(
              controller: _query,
              placeholder: 'Venue name or address',
              autofocus: true,
            ),
          ),

          // Results list.
          Expanded(
            child: _searching
                ? const Center(child: CupertinoActivityIndicator())
                : _predictions.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            _query.text.isEmpty
                                ? 'Start typing to search for a venue'
                                : 'No results found',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: CupertinoColors.secondaryLabel
                                  .resolveFrom(context),
                            ),
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _predictions.length,
                        separatorBuilder: (_, __) => Container(
                          height: 0.5,
                          margin: const EdgeInsets.only(left: 54),
                          color: CupertinoColors.separator.resolveFrom(context),
                        ),
                        itemBuilder: (context, i) {
                          final p = _predictions[i];
                          return _ResultRow(
                            prediction: p,
                            onTap: () => _select(p),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

// ── Single search result row ──────────────────────────────────────────────────

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.prediction,
    required this.onTap,
  });

  final VenuePrediction prediction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${prediction.name}, ${prediction.address}',
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          color: CupertinoColors.systemBackground.resolveFrom(context),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(
            children: [
              Icon(
                CupertinoIcons.map_pin,
                size: 20,
                color: CupertinoColors.tertiaryLabel.resolveFrom(context),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      prediction.name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: CupertinoColors.label.resolveFrom(context),
                      ),
                    ),
                    if (prediction.address.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        prediction.address,
                        style: TextStyle(
                          fontSize: 13,
                          color: CupertinoColors.secondaryLabel
                              .resolveFrom(context),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
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

// ── Date picker sheet with booking status calendar ────────────────────────────

/// A modal bottom sheet that wraps [BookingCalendarPicker].
///
/// Accepts a pre-resolved [AsyncValue] snapshot of the date-status map so that
/// callers can pass an already-cached value without triggering a redundant
/// network request.  The sheet handles all three AsyncValue states internally.
class _DatePickerSheet extends StatefulWidget {
  const _DatePickerSheet({
    required this.initialDate,
    required this.statusesAsync,
    required this.onDone,
  });

  final DateTime initialDate;

  /// Snapshot of [bookingDateInfoProvider] — may be loading/error/data.
  final AsyncValue<Map<String, BookingDateInfo>> statusesAsync;

  /// Called with the confirmed date when the user taps Done.
  final ValueChanged<DateTime> onDone;

  @override
  State<_DatePickerSheet> createState() => _DatePickerSheetState();
}

class _DatePickerSheetState extends State<_DatePickerSheet> {
  late DateTime _pending;

  @override
  void initState() {
    super.initState();
    _pending = widget.initialDate;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        // Dynamic height: calendar + legend is taller than a standard picker.
        // Use intrinsic height capped so it never overflows on small phones.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.65,
        ),
        decoration: BoxDecoration(
          color: CupertinoColors.systemBackground.resolveFrom(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Sheet handle + Done button ──────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
              child: Row(
                children: [
                  // Drag handle.
                  Expanded(
                    child: Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: CupertinoColors.tertiaryLabel
                              .resolveFrom(context),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () {
                      widget.onDone(_pending);
                      Navigator.of(context).pop();
                    },
                    child: const Text('Done',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),

            // ── Calendar ────────────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                child: widget.statusesAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(child: CupertinoActivityIndicator()),
                  ),
                  error: (_, __) => _CalendarWithStatuses(
                    // Show the calendar anyway on error — just without markers.
                    pending: _pending,
                    statuses: const {},
                    onDateSelected: (d) => setState(() => _pending = d),
                  ),
                  data: (statuses) => _CalendarWithStatuses(
                    pending: _pending,
                    statuses: statuses,
                    onDateSelected: (d) => setState(() => _pending = d),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Thin wrapper that renders [BookingCalendarPicker] with consistent padding.
class _CalendarWithStatuses extends StatelessWidget {
  const _CalendarWithStatuses({
    required this.pending,
    required this.statuses,
    required this.onDateSelected,
  });

  final DateTime pending;
  final Map<String, BookingDateInfo> statuses;
  final ValueChanged<DateTime> onDateSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: BookingCalendarPicker(
        selectedDate: pending,
        dateStatuses: statuses,
        onDateSelected: onDateSelected,
      ),
    );
  }
}
