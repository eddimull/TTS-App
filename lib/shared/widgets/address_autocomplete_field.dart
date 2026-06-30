import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tts_bandmate/core/config/app_config.dart';

import '../../features/bookings/data/venue_search_service.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';

/// Structured result from the Geocoding API `address_components` array.
///
/// Exposes both the long and short forms of the state so callers can match
/// against whichever they store — a free-text field typically wants the short
/// abbreviation (e.g. "LA"), while a state-lookup dropdown keyed by full name
/// wants the long form (e.g. "Louisiana").
class AddressComponents {
  const AddressComponents({
    required this.streetNumber,
    required this.route,
    required this.city,
    required this.stateLong,
    required this.stateShort,
    required this.zip,
  });

  final String streetNumber;
  final String route;
  final String city;
  final String stateLong;
  final String stateShort;
  final String zip;

  /// Combines street number + route into a single street address string,
  /// e.g. "123 Main St". Falls back gracefully when either part is absent.
  String get streetAddress {
    if (streetNumber.isEmpty && route.isEmpty) return '';
    if (streetNumber.isEmpty) return route;
    if (route.isEmpty) return streetNumber;
    return '$streetNumber $route';
  }
}

/// Separate Dio instance for the public Geocoding REST API — intentionally not
/// the app's api_client.dart instance, so no auth header is attached. Uses the
/// REST key (same as venue_picker.dart), not the native Maps SDK key.
final Dio _geocodeDio = Dio();

/// Calls the Geocoding REST API and returns structured address components, or
/// null if the call fails / returns no results.
Future<AddressComponents?> geocodeToComponents(String address) async {
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
    String stateLong = '';
    String stateShort = '';
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
        stateLong = longName;
        stateShort = shortName;
      } else if (types.contains('postal_code')) {
        zip = longName;
      }
    }

    return AddressComponents(
      streetNumber: streetNumber,
      route: route,
      city: city,
      stateLong: stateLong,
      stateShort: stateShort,
      zip: zip,
    );
  } catch (_) {
    return null;
  }
}

/// A labeled Cupertino street-address field with debounced Google Places
/// autocomplete and geocode-on-select. Mirrors the band-settings pattern so the
/// two address editors behave identically.
///
/// The widget owns the dropdown overlay, debounce, and geocoding. When the user
/// picks a suggestion it writes the resolved street into [controller] and hands
/// the full structured components back via [onResolved] so the caller can fill
/// its own city/state/zip fields (which may be text fields or lookup pickers).
///
/// Stays permissive — like every other address editor in the app, it never
/// blocks input or requires a "complete" address.
class AddressAutocompleteField extends ConsumerStatefulWidget {
  const AddressAutocompleteField({
    super.key,
    required this.label,
    required this.controller,
    required this.onResolved,
    this.placeholder,
    this.error,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;

  /// Called after a suggestion is geocoded, with the structured components.
  /// The street is already written into [controller]; the caller fills the
  /// remaining fields (city/state/zip) however it stores them.
  final ValueChanged<AddressComponents> onResolved;

  final String? placeholder;

  /// Inline validation error to show below the field (e.g. a backend 422).
  final String? error;

  /// Forwarded from the underlying field's onChanged — fires on every keystroke
  /// so callers can react (e.g. recompute a derived "address changed" flag).
  final ValueChanged<String>? onChanged;

  @override
  ConsumerState<AddressAutocompleteField> createState() =>
      _AddressAutocompleteFieldState();
}

class _AddressAutocompleteFieldState
    extends ConsumerState<AddressAutocompleteField> {
  final LayerLink _link = LayerLink();
  final FocusNode _focus = FocusNode();
  OverlayEntry? _dropdownEntry;
  List<VenuePrediction> _predictions = [];
  bool _searching = false;
  bool _geocoding = false;
  Timer? _debounce;
  String? _lastSearchedText;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    _focus.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(covariant AddressAutocompleteField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the parent swaps in a different controller, move our listener over so
    // the old one isn't left with a stale listener and the new one still drives
    // autocomplete.
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _removeDropdown();
    widget.controller.removeListener(_onChanged);
    _focus
      ..removeListener(_onFocusChanged)
      ..dispose();
    super.dispose();
  }

  void _onChanged() {
    final text = widget.controller.text;
    if (text == _lastSearchedText) return;

    if (text.trim().isEmpty) {
      _debounce?.cancel();
      _lastSearchedText = text;
      _removeDropdown();
      return;
    }

    _debounce?.cancel();
    _debounce =
        Timer(const Duration(milliseconds: 300), () => _runSearch(text));
  }

  void _onFocusChanged() {
    // Delay one frame so a tap on a dropdown row registers before we remove it.
    if (!_focus.hasFocus) {
      Future.microtask(_removeDropdown);
    }
  }

  Future<void> _runSearch(String text) async {
    if (!mounted) return;
    _lastSearchedText = text;

    final service = ref.read(venueSearchServiceProvider);
    setState(() => _searching = true);
    _rebuildDropdown();

    final results = await service.search(text);
    if (!mounted || widget.controller.text != text) return;

    setState(() {
      _predictions = results;
      _searching = false;
    });

    if (results.isNotEmpty) {
      _rebuildDropdown();
    } else {
      _removeDropdown();
    }
  }

  void _rebuildDropdown() {
    _removeDropdown();
    if (!_searching && _predictions.isEmpty) return;

    final overlay = Overlay.of(context, rootOverlay: false);
    _dropdownEntry = OverlayEntry(
      builder: (_) => _AddressDropdown(
        link: _link,
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
    _debounce?.cancel();
    _removeDropdown();

    // Silence the listener while we programmatically set the field.
    widget.controller.removeListener(_onChanged);

    if (prediction.placeId.isEmpty) {
      widget.controller.text = prediction.name;
      _lastSearchedText = prediction.name;
      widget.controller.addListener(_onChanged);
      // Programmatic text changes don't fire CupertinoTextField.onChanged, so
      // notify the parent ourselves — otherwise selecting a suggestion wouldn't
      // count as an address change (e.g. the "When did you move?" prompt).
      widget.onChanged?.call(prediction.name);
      return;
    }

    final fullAddress = [prediction.name, prediction.address]
        .where((s) => s.isNotEmpty)
        .join(', ');

    setState(() => _geocoding = true);
    try {
      final components = await geocodeToComponents(fullAddress);
      if (!mounted) return;

      final street = (components != null && components.streetAddress.isNotEmpty)
          ? components.streetAddress
          : prediction.name;
      setState(() {
        widget.controller.text = street;
        _lastSearchedText = street;
      });
      if (components != null) widget.onResolved(components);
      // See note above: a programmatic set doesn't trigger onChanged.
      widget.onChanged?.call(street);
    } finally {
      // Only re-attach when still mounted — otherwise we'd register a listener
      // on the external controller pointing at a disposed State.
      if (mounted) {
        setState(() => _geocoding = false);
        widget.controller.addListener(_onChanged);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final labelColor = CupertinoColors.secondaryLabel.resolveFrom(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(widget.label,
                  style: TextStyle(fontSize: 13, color: labelColor)),
              if (_geocoding) ...[
                const SizedBox(width: 8),
                const CupertinoActivityIndicator(),
              ],
            ],
          ),
          const SizedBox(height: 4),
          CompositedTransformTarget(
            link: _link,
            child: CupertinoTextField(
              controller: widget.controller,
              focusNode: _focus,
              placeholder: widget.placeholder,
              onChanged: widget.onChanged,
            ),
          ),
          if (widget.error != null) ...[
            const SizedBox(height: 4),
            Text(
              widget.error!,
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
}

// ── Autocomplete dropdown overlay ─────────────────────────────────────────────

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
    const rowHeight = 60.0;
    const maxVisibleRows = 4;
    final listHeight = searching
        ? 48.0
        : (predictions.length.clamp(1, maxVisibleRows) * rowHeight).toDouble();

    return Positioned(
      left: 0,
      top: 0,
      child: CompositedTransformFollower(
        link: link,
        showWhenUnlinked: false,
        offset: const Offset(0, 38),
        child: SizedBox(
          width: MediaQuery.of(context).size.width - 32,
          height: listHeight,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              color:
                  CupertinoColors.tertiarySystemBackground.resolveFrom(context),
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
                      itemBuilder: (_, i) => _DropdownRow(
                        prediction: predictions[i],
                        onTap: () => onSelect(predictions[i]),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DropdownRow extends StatelessWidget {
  const _DropdownRow({required this.prediction, required this.onTap});

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
                color: context.tertiaryText,
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
                        color: context.primaryText,
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
                          color: context.secondaryText,
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
