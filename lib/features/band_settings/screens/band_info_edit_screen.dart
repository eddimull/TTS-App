import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../data/models/band_detail.dart';
import '../providers/band_settings_provider.dart';

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

  Widget _field(
    String label,
    TextEditingController controller,
    String fieldKey, {
    TextInputType? keyboardType,
  }) {
    final error = _fieldErrors[fieldKey];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: CupertinoColors.secondaryLabel,
            ),
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

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Edit Band Info'),
        trailing: (_saving || _uploadingLogo)
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
                        color: CupertinoColors.systemGrey5,
                        child: _logoUrl != null
                            ? Image.network(
                                _logoUrl!,
                                width: 96,
                                height: 96,
                                fit: BoxFit.cover,
                              )
                            : const Icon(
                                CupertinoIcons.camera,
                                size: 32,
                                color: CupertinoColors.systemGrey,
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
            _field('Street Address', _address, 'address'),
            _field('City', _city, 'city'),
            _field('State', _state, 'state'),
            _field('Zip', _zip, 'zip', keyboardType: TextInputType.number),
          ],
        ),
      ),
    );
  }
}
