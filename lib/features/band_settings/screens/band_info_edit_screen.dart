import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tts_bandmate/core/config/app_config.dart';
import 'package:tts_bandmate/shared/cache/cache_invalidator.dart';
import '../data/models/band_detail.dart';
import '../providers/band_settings_provider.dart';
import '../../bookings/data/venue_search_service.dart';

// ── Address component parsing ─────────────────────────────────────────────────

/// Structured result from the Geocoding API `address_components` array.
class _AddressComponents {
  const _AddressComponents({
    required this.streetNumber,
    required this.route,
    required this.city,
    required this.state,
    required this.zip,
  });

  final String streetNumber;
  final String route;
  final String city;
  final String state;
  final String zip;

  /// Combines street number + route into a single street address string,
  /// e.g. "123 Main St".  Falls back gracefully when either part is absent.
  String get streetAddress {
    if (streetNumber.isEmpty && route.isEmpty) return '';
    if (streetNumber.isEmpty) return route;
    if (route.isEmpty) return streetNumber;
    return '$streetNumber $route';
  }
}

/// Calls the Geocoding REST API and returns structured address components, or
/// null if the call fails / returns no results.
///
/// Uses the same REST key as [geocodeAddress] in venue_picker.dart — not the
/// native Maps SDK key.  Intentionally separate from the app's api_client.dart
/// Dio instance so no auth header is attached.
final Dio _geocodeDio = Dio();

Future<_AddressComponents?> _geocodeToComponents(String address) async {
  if (address.trim().isEmpty || AppConfig.googlePlacesApiKey.isEmpty) {
    return null;
  }
  try {
    final response = await _geocodeDio.get<Map<String, dynamic>>(
      'https://maps.googleapis.com/maps/api/geocode/json',
      queryParameters: {
        'address': address,
        'key': AppConfig.googlePlacesApiKey,
      },
    );
    final results = response.data?['results'] as List<dynamic>?;
    if (results == null || results.isEmpty) return null;

    final components =
        (results.first as Map<String, dynamic>)['address_components']
            as List<dynamic>?;
    if (components == null) return null;

    String streetNumber = '';
    String route = '';
    String city = '';
    String state = '';
    String zip = '';

    for (final component in components) {
      final types = (component['types'] as List<dynamic>?)
              ?.map((t) => t.toString())
              .toList() ??
          [];
      final longName = component['long_name']?.toString() ?? '';
      final shortName = component['short_name']?.toString() ?? '';

      if (types.contains('street_number')) {
        streetNumber = longName;
      } else if (types.contains('route')) {
        route = longName;
      } else if (types.contains('locality')) {
        city = longName;
      } else if (types.contains('administrative_area_level_1')) {
        // Use abbreviated form for state (e.g. "CA" rather than "California").
        state = shortName;
      } else if (types.contains('postal_code')) {
        zip = longName;
      }
    }

    return _AddressComponents(
      streetNumber: streetNumber,
      route: route,
      city: city,
      state: state,
      zip: zip,
    );
  } catch (_) {
    return null;
  }
}

// ── Screen ────────────────────────────────────────────────────────────────────

class BandInfoEditScreen extends ConsumerStatefulWidget {
  const BandInfoEditScreen({
    super.key,
    required this.bandId,
    required this.initial,
  });

  final int bandId;
  final BandDetail initial;

  @override
  ConsumerState<BandInfoEditScreen> createState() => _BandInfoEditScreenState();
}

class _BandInfoEditScreenState extends ConsumerState<BandInfoEditScreen> {
  late final TextEditingController _name;
  late final TextEditingController _siteName;
  late final TextEditingController _address;
  late final TextEditingController _city;
  late final TextEditingController _state;
  late final TextEditingController _zip;
  bool _saving = false;
  bool _uploadingLogo = false;
  bool _geocoding = false;
  String? _logoUrl;
  Map<String, String> _fieldErrors = {};

  // ── Autocomplete dropdown state ─────────────────────────────────────────────

  /// Overlay entry for the suggestions dropdown. Null when the dropdown is
  /// not visible. Always removed in dispose() and whenever it is dismissed.
  OverlayEntry? _dropdownEntry;

  /// LayerLink that ties the CompositedTransformFollower (the overlay dropdown)
  /// to the CompositedTransformTarget (the address text field).
  final LayerLink _addressFieldLink = LayerLink();

  /// Current predictions shown in the dropdown. Replaced on each search
  /// response; cleared when the dropdown is dismissed.
  List<VenuePrediction> _predictions = [];

  /// Whether a search request is currently in-flight.
  bool _searching = false;

  /// Debounce timer — cancelled and rescheduled on each keystroke.
  Timer? _debounce;

  /// The last text that was actually searched so we can skip redundant calls
  /// (the controller fires its listener for cursor moves too).
  String? _lastSearchedText;

  /// FocusNode for the address field — used to detect focus-loss dismissal.
  final FocusNode _addressFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    final d = widget.initial;
    _name = TextEditingController(text: d.name);
    _siteName = TextEditingController(text: d.siteName);
    _address = TextEditingController(text: d.address);
    _city = TextEditingController(text: d.city);
    _state = TextEditingController(text: d.state);
    _zip = TextEditingController(text: d.zip);
    _logoUrl = d.logoUrl;

    _address.addListener(_onAddressChanged);
    _addressFocus.addListener(_onAddressFocusChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _removeDropdown();
    _addressFocus
      ..removeListener(_onAddressFocusChanged)
      ..dispose();
    _name.dispose();
    _siteName.dispose();
    _address
      ..removeListener(_onAddressChanged)
      ..dispose();
    _city.dispose();
    _state.dispose();
    _zip.dispose();
    super.dispose();
  }

  // ── Autocomplete logic ──────────────────────────────────────────────────────

  void _onAddressChanged() {
    final text = _address.text;

    // Skip scheduling a search when only cursor/selection changed.
    if (text == _lastSearchedText) return;

    // Clear the dropdown immediately if the field is emptied.
    if (text.trim().isEmpty) {
      _debounce?.cancel();
      _lastSearchedText = text;
      _removeDropdown();
      return;
    }

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _runSearch(text));
  }

  void _onAddressFocusChanged() {
    // When the address field loses focus the dropdown should disappear.
    // We delay by one frame so that a tap on a dropdown row registers first —
    // otherwise the overlay is removed before the GestureDetector fires.
    if (!_addressFocus.hasFocus) {
      Future.microtask(_removeDropdown);
    }
  }

  Future<void> _runSearch(String text) async {
    if (!mounted) return;

    _lastSearchedText = text;

    final service = ref.read(venueSearchServiceProvider);

    // Mark searching — rebuild dropdown to show spinner.
    setState(() => _searching = true);
    _rebuildDropdown();

    final results = await service.search(text);

    // Discard stale response if the query has changed since this call started.
    if (!mounted || _address.text != text) return;

    setState(() {
      _predictions = results;
      _searching = false;
    });

    // Show dropdown only when there are results to display.
    if (results.isNotEmpty) {
      _rebuildDropdown();
    } else {
      _removeDropdown();
    }
  }

  /// Inserts (or replaces) the overlay dropdown entry anchored below the
  /// address field using [CompositedTransformFollower].
  void _rebuildDropdown() {
    _removeDropdown();

    // Nothing to show yet — exit early unless we're in the searching state.
    if (!_searching && _predictions.isEmpty) return;

    final overlay = Overlay.of(context, rootOverlay: false);

    _dropdownEntry = OverlayEntry(
      builder: (overlayContext) => _AddressDropdown(
        link: _addressFieldLink,
        predictions: _predictions,
        searching: _searching,
        onSelect: _onPredictionSelected,
      ),
    );

    overlay.insert(_dropdownEntry!);
  }

  void _removeDropdown() {
    _dropdownEntry?.remove();
    _dropdownEntry = null;
  }

  Future<void> _onPredictionSelected(VenuePrediction prediction) async {
    // Dismiss dropdown immediately and stop any pending debounce.
    _debounce?.cancel();
    _removeDropdown();

    // Silence the listener while we programmatically set the field value so
    // we don't trigger another search cycle.
    _address.removeListener(_onAddressChanged);

    if (prediction.placeId.isEmpty) {
      // Free-text path — no geocoding to do.
      _address.text = prediction.name;
      _lastSearchedText = prediction.name;
      _address.addListener(_onAddressChanged);
      return;
    }

    final fullAddress = [prediction.name, prediction.address]
        .where((s) => s.isNotEmpty)
        .join(', ');

    // Show the geocoding spinner next to the label.
    setState(() => _geocoding = true);

    try {
      final components = await _geocodeToComponents(fullAddress);
      if (!mounted) return;

      setState(() {
        final street = (components != null && components.streetAddress.isNotEmpty)
            ? components.streetAddress
            : prediction.name;
        _address.text = street;
        _lastSearchedText = street;

        if (components != null) {
          if (components.city.isNotEmpty) _city.text = components.city;
          if (components.state.isNotEmpty) _state.text = components.state;
          if (components.zip.isNotEmpty) _zip.text = components.zip;
        }
      });
    } finally {
      if (mounted) setState(() => _geocoding = false);
      // Re-attach listener after programmatic writes are complete.
      _address.addListener(_onAddressChanged);
    }
  }

  // ── Logo / save ─────────────────────────────────────────────────────────────

  Future<void> _pickLogo() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;
    setState(() => _uploadingLogo = true);
    try {
      final bytes = await file.readAsBytes();
      await ref
          .read(bandSettingsRepositoryProvider)
          .uploadLogo(widget.bandId, bytes, file.name);
      // Re-fetch detail to get updated logo_url
      await ref.read(bandSettingsProvider(widget.bandId).notifier).load();
      // Refresh authProvider.bands so every other screen (dashboard, nav,
      // BandIdentityChip, etc.) picks up the new logo_url too.
      await ref.read(cacheInvalidatorProvider).onBandIdentityChanged();
      final detail =
          ref.read(bandSettingsProvider(widget.bandId)).value?.detail;
      if (mounted) setState(() => _logoUrl = detail?.logoUrl);
    } catch (_) {
      if (mounted) {
        showCupertinoDialog<void>(
          context: context,
          builder: (_) => CupertinoAlertDialog(
            title: const Text('Upload Failed'),
            content: const Text('Could not upload logo. Please try again.'),
            actions: [
              CupertinoDialogAction(
                child: const Text('OK'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingLogo = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _fieldErrors = {};
    });
    final updated = widget.initial.copyWith(
      name: _name.text.trim(),
      siteName: _siteName.text.trim(),
      address: _address.text.trim(),
      city: _city.text.trim(),
      state: _state.text.trim(),
      zip: _zip.text.trim(),
    );
    try {
      await ref
          .read(bandSettingsProvider(widget.bandId).notifier)
          .updateDetail(updated);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      // Try to extract field-level validation errors from the exception message.
      // Server returns 422 with errors keyed by field name (e.g. name, site_name).
      final errors = _parseValidationErrors(e);
      if (errors.isNotEmpty) {
        setState(() => _fieldErrors = errors);
      } else {
        showCupertinoDialog<void>(
          context: context,
          builder: (_) => CupertinoAlertDialog(
            title: const Text('Save Failed'),
            content: Text(e.toString()),
            actions: [
              CupertinoDialogAction(
                child: const Text('OK'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Parses Laravel 422 validation errors from a DioException.
  /// Returns a map of field key → first error message, or empty map if not a
  /// validation error.
  Map<String, String> _parseValidationErrors(Object e) {
    if (e is! DioException) return {};
    final data = e.response?.data;
    if (data is! Map) return {};
    final errors = data['errors'];
    if (errors is! Map) return {};
    return {
      for (final entry in errors.entries)
        entry.key as String: (entry.value is List && (entry.value as List).isNotEmpty)
            ? (entry.value as List).first.toString()
            : entry.value.toString(),
    };
  }

  // ── Field builder ─────────────────────────────────────────────────────────

  Widget _field(
    String label,
    TextEditingController controller,
    String fieldKey, {
    TextInputType? keyboardType,
  }) {
    final error = _fieldErrors[fieldKey];
    // CupertinoColors.secondaryLabel is a CupertinoDynamicColor — it must be
    // resolved against BuildContext at runtime so it adapts to dark mode.
    // Using it in a const TextStyle would freeze it to the light-mode value.
    final labelColor =
        CupertinoColors.secondaryLabel.resolveFrom(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 13, color: labelColor),
          ),
          const SizedBox(height: 4),
          CupertinoTextField(
            controller: controller,
            keyboardType: keyboardType,
          ),
          if (error != null) ...[
            const SizedBox(height: 4),
            Text(
              error,
              style: const TextStyle(
                fontSize: 12,
                color: CupertinoColors.destructiveRed,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Address section — street field with inline autocomplete ──────────────────

  /// Builds the "Street Address" label (with geocoding spinner) and the
  /// text field wrapped in a [CompositedTransformTarget] so the suggestions
  /// overlay can anchor itself directly below it.
  Widget _addressSection() {
    final labelColor = CupertinoColors.secondaryLabel.resolveFrom(context);
    final error = _fieldErrors['address'];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Street Address',
                style: TextStyle(fontSize: 13, color: labelColor),
              ),
              if (_geocoding) ...[
                const SizedBox(width: 8),
                const CupertinoActivityIndicator(),
              ],
            ],
          ),
          const SizedBox(height: 4),
          // CompositedTransformTarget marks the exact position of the field
          // so the overlay can follow it as the page scrolls or resizes.
          CompositedTransformTarget(
            link: _addressFieldLink,
            child: CupertinoTextField(
              controller: _address,
              focusNode: _addressFocus,
              placeholder: 'Street address',
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 4),
            Text(
              error,
              style: const TextStyle(
                fontSize: 12,
                color: CupertinoColors.destructiveRed,
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final busy = _saving || _uploadingLogo || _geocoding;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Edit Band Info'),
        trailing: busy
            ? const CupertinoActivityIndicator()
            : CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _save,
                child: const Text('Save'),
              ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Logo picker — tapping opens gallery; spinner overlaid during upload
            Center(
              child: GestureDetector(
                onTap: _uploadingLogo ? null : _pickLogo,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // ClipOval + Container replaces CircleAvatar (Material) with a
                    // Cupertino-compatible circular image/icon widget.
                    ClipOval(
                      child: Container(
                        width: 96,
                        height: 96,
                        // resolveFrom ensures the placeholder background adapts
                        // correctly to dark mode (systemGrey5 is a dynamic color).
                        color: CupertinoColors.systemGrey5.resolveFrom(context),
                        child: _logoUrl != null
                            ? Image.network(
                                _logoUrl!,
                                width: 96,
                                height: 96,
                                fit: BoxFit.cover,
                              )
                            : Icon(
                                CupertinoIcons.camera,
                                size: 32,
                                // systemGrey resolves correctly in dark mode here;
                                // using resolveFrom keeps it adaptive.
                                color: CupertinoColors.systemGrey
                                    .resolveFrom(context),
                              ),
                      ),
                    ),
                    if (_uploadingLogo) const CupertinoActivityIndicator(),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            _field('Band Name', _name, 'name'),
            _field('Page URL', _siteName, 'site_name'),
            _addressSection(),
            _field('City', _city, 'city'),
            _field('State', _state, 'state'),
            _field('Zip', _zip, 'zip', keyboardType: TextInputType.number),
          ],
        ),
      ),
    );
  }
}

// ── Autocomplete dropdown overlay ─────────────────────────────────────────────
//
// Rendered inside the [Overlay] stack so it floats above the form without
// pushing other fields down.  [CompositedTransformFollower] pins it to the
// bottom-left of the address field regardless of scroll position.

class _AddressDropdown extends StatelessWidget {
  const _AddressDropdown({
    required this.link,
    required this.predictions,
    required this.searching,
    required this.onSelect,
  });

  final LayerLink link;
  final List<VenuePrediction> predictions;
  final bool searching;
  final ValueChanged<VenuePrediction> onSelect;

  @override
  Widget build(BuildContext context) {
    // Max ~4 rows before the list scrolls so it doesn't consume the whole screen.
    const rowHeight = 60.0;
    const maxVisibleRows = 4;
    final listHeight = searching
        ? 48.0
        : (predictions.length.clamp(1, maxVisibleRows) * rowHeight).toDouble();

    return Positioned(
      // CompositedTransformFollower handles its own positioning; Positioned
      // here just removes it from the normal flow so it doesn't shift content.
      left: 0,
      top: 0,
      child: CompositedTransformFollower(
        link: link,
        showWhenUnlinked: false,
        // Offset by the height of the CupertinoTextField (≈ 36 px) + 2 px gap.
        offset: const Offset(0, 38),
        child: SizedBox(
          // Constrain width to match the field width. MediaQuery width minus
          // 32 px matches the 16 px horizontal padding on each side in the form.
          width: MediaQuery.of(context).size.width - 32,
          height: listHeight,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              // tertiarySystemBackground gives the dropdown a slightly recessed
              // tint vs. systemBackground — adapts to dark mode automatically.
              color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
              child: searching
                  ? const Center(child: CupertinoActivityIndicator())
                  : ListView.separated(
                      padding: EdgeInsets.zero,
                      itemCount: predictions.length,
                      separatorBuilder: (_, __) => Container(
                        height: 0.5,
                        margin: const EdgeInsets.only(left: 44),
                        color: CupertinoColors.separator.resolveFrom(context),
                      ),
                      itemBuilder: (_, i) {
                        final p = predictions[i];
                        return _DropdownRow(
                          prediction: p,
                          onTap: () => onSelect(p),
                        );
                      },
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Single suggestion row ─────────────────────────────────────────────────────

class _DropdownRow extends StatelessWidget {
  const _DropdownRow({
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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(
                CupertinoIcons.map_pin,
                size: 18,
                color: CupertinoColors.tertiaryLabel.resolveFrom(context),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      prediction.name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: CupertinoColors.label.resolveFrom(context),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (prediction.address.isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        prediction.address,
                        style: TextStyle(
                          fontSize: 12,
                          color: CupertinoColors.secondaryLabel
                              .resolveFrom(context),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
