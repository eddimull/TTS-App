import 'package:intl/intl.dart';

/// Converts a time string to a 12-hour AM/PM string.
/// Accepts "HH:mm", "HH:mm:ss", or ISO 8601 datetime strings.
/// Returns [fallback] if [raw] is null/empty or unparseable.
String toAmPm(String? raw, {String fallback = ''}) {
  if (raw == null || raw.isEmpty) return fallback;
  // Try full ISO datetime first
  final iso = DateTime.tryParse(raw);
  if (iso != null) return DateFormat('h:mm a').format(iso);
  // Try "HH:mm" or "HH:mm:ss"
  try {
    final parts = raw.split(':');
    final h = int.parse(parts[0]);
    final m = int.parse(parts[1]);
    return DateFormat('h:mm a').format(DateTime(2000, 1, 1, h, m));
  } catch (_) {
    return raw;
  }
}

/// Formats a date string with a start time and optional end time.
/// e.g. "Monday, March 30, 2026, 7:00 PM – 10:00 PM"
String formatDateWithTimeRange(
  String date,
  String? startTime,
  String? endTime, {
  String dateFormat = 'EEEE, MMMM d, yyyy',
}) {
  try {
    final dt = DateTime.parse(date);
    final dateStr = DateFormat(dateFormat).format(dt);
    if (startTime != null && startTime.isNotEmpty) {
      if (endTime != null && endTime.isNotEmpty) {
        return '$dateStr, ${toAmPm(startTime)} – ${toAmPm(endTime)}';
      }
      return '$dateStr at ${toAmPm(startTime)}';
    }
    return dateStr;
  } catch (_) {
    if (startTime != null && startTime.isNotEmpty) {
      return '$date at ${toAmPm(startTime)}';
    }
    return date;
  }
}
