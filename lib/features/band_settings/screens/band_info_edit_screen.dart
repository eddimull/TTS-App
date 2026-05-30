import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tts_bandmate/core/config/app_config.dart';
import 'package:tts_bandmate/shared/cache/cache_invalidator.dart';
import '../data/models/band_detail.dart';
import '../providers/band_settings_provider.dart';
import '../../bookings/data/venue_search_service.dart';
import '../../bookings/widgets/venue_picker.dart' show VenueSearchSheet;

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
  }

  @override
  void dispose() {
    _name.dispose();
    _siteName.dispose();
    _address.dispose();
    _city.dispose();
    _state.dispose();
    _zip.dispose();
    super.dispose();
  }

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

  // ── Address autocomplete ────────────────────────────────────────────────────

  /// Opens [VenueSearchSheet] to search for an address. On selection, calls
  /// the Geocoding REST API to break the returned address into components and
  /// populates street, city, state, and zip fields.
  ///
  /// Free-typed entries (placeId == '') skip geocoding and write the raw text
  /// into the street address field only — the user must fill city/state/zip.
  Future<void> _openAddressSearch() async {
    final service = ref.read(venueSearchServiceProvider);

    final prediction = await Navigator.of(context).push<VenuePrediction>(
      CupertinoPageRoute(
        builder: (_) => VenueSearchSheet(
          // Seed the search box with the current street address so the user
          // can refine rather than start from scratch.
          initialText: _address.text.trim(),
          service: service,
        ),
      ),
    );

    if (prediction == null || !mounted) return;

    // Free-text path (placeId == ''): use the typed name as the street address
    // only — geocoding would be unreliable on an incomplete string.
    if (prediction.placeId.isEmpty) {
      setState(() => _address.text = prediction.name);
      return;
    }

    // For a real Places prediction, geocode the full address string to extract
    // structured components (street, city, state, zip).
    final fullAddress = [prediction.name, prediction.address]
        .where((s) => s.isNotEmpty)
        .join(', ');

    setState(() => _geocoding = true);
    try {
      final components = await _geocodeToComponents(fullAddress);
      if (!mounted) return;

      if (components != null) {
        setState(() {
          // Prefer the structured street address from geocoding; fall back to
          // the prediction name when the geocoder returns no route component.
          final street = components.streetAddress.isNotEmpty
              ? components.streetAddress
              : prediction.name;
          _address.text = street;
          if (components.city.isNotEmpty) _city.text = components.city;
          if (components.state.isNotEmpty) _state.text = components.state;
          if (components.zip.isNotEmpty) _zip.text = components.zip;
        });
      } else {
        // Geocode call failed or returned nothing — fall back to prediction text
        // so the user has something to work from.
        setState(() {
          _address.text = prediction.name;
          if (prediction.address.isNotEmpty) {
            // The prediction.address is typically "City, State, Country".
            // Don't try to parse it — just put the name in and leave city/state
            // for the user to fill.
          }
        });
      }
    } finally {
      if (mounted) setState(() => _geocoding = false);
    }
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

  // ── Address section — street field + autocomplete button ──────────────────

  /// Builds the "Street Address" field plus the autocomplete search button that
  /// appears to the right of the label.  Geocoding spinner replaces the button
  /// while a Places lookup is in flight.
  Widget _addressSection() {
    final labelColor =
        CupertinoColors.secondaryLabel.resolveFrom(context);
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
              const Spacer(),
              if (_geocoding)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: CupertinoActivityIndicator(),
                )
              else
                Semantics(
                  label: 'Search for address',
                  button: true,
                  child: CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: _saving ? null : _openAddressSearch,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          CupertinoIcons.search,
                          size: 14,
                          // activeBlue resolves correctly in both light and dark.
                          color: CupertinoColors.activeBlue.resolveFrom(context),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Autocomplete',
                          style: TextStyle(
                            fontSize: 13,
                            color:
                                CupertinoColors.activeBlue.resolveFrom(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          CupertinoTextField(
            controller: _address,
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
