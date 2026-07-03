import '../../../core/config/app_config.dart';

/// Path segment that precedes the invite key in an invite URL:
/// `<host>/invite/<key>`.
const String _invitePathSegment = 'invite';

/// Normalize a scanned or typed value into a bare invite key.
///
/// Accepts either a raw key (`"abc123"`) or an invite URL
/// (`"https://tts.band/invite/abc123"`, with optional trailing slash or query).
/// Returns `null` when the input is blank or is an `/invite/` URL missing its
/// key segment.
String? extractInviteKey(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;

  final uri = Uri.tryParse(trimmed);
  final looksLikeUrl = uri != null && uri.hasScheme;

  if (looksLikeUrl) {
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    final idx = segments.indexOf(_invitePathSegment);
    if (idx == -1 || idx + 1 >= segments.length) return null;
    final key = segments[idx + 1];
    return key.isEmpty ? null : key;
  }

  // Not a URL — treat the whole trimmed string as the key.
  return trimmed;
}

/// Build the public invite URL that gets encoded into the QR / share sheet.
String buildInviteUrl(String key) => '${AppConfig.inviteBaseUrl}/invite/$key';
