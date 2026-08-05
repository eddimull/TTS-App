import 'package:url_launcher/url_launcher.dart';

/// Builds a Google Maps search URI for a place.
///
/// Precedence: coordinates → address → name. Returns null when nothing
/// usable is provided. Google Maps URLs open the native app on iOS and
/// Android and the browser elsewhere.
Uri? mapsSearchUri({double? lat, double? lng, String? address, String? name}) {
  if (lat != null && lng != null) {
    return Uri.parse('https://maps.google.com/?q=$lat,$lng');
  }
  if (address != null && address.isNotEmpty) {
    return Uri.parse('https://maps.google.com/?q=${Uri.encodeComponent(address)}');
  }
  if (name != null && name.isNotEmpty) {
    return Uri.parse('https://maps.google.com/?q=${Uri.encodeComponent(name)}');
  }
  return null;
}

/// Launches maps for the given place; silent no-op when unresolvable.
Future<void> openInMaps(
    {double? lat, double? lng, String? address, String? name}) async {
  final uri = mapsSearchUri(lat: lat, lng: lng, address: address, name: name);
  if (uri == null) return;
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
