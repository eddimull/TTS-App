import 'package:flutter/cupertino.dart';

/// A lightweight, source-agnostic descriptor of a person shown in the shared
/// [ContactDetailScreen].
///
/// Band members, substitutes, roster members, and searched contacts all map
/// onto this single shape via the `from*` adapters below, so every "who is this
/// person" tap across the app lands on the same canonical detail view.
@immutable
class ContactRef {
  const ContactRef({
    required this.name,
    this.email,
    this.phone,
    this.role,
    this.section,
    this.userId,
    this.isOwner = false,
    this.isSub = false,
    this.subtitle,
  });

  final String name;
  final String? email;
  final String? phone;

  /// Instrument / position, e.g. "Bass", "Trumpet".
  final String? role;

  /// Section / band-role grouping, e.g. "RHYTHM", "HORNS".
  final String? section;

  /// The TTS user id when this contact is a registered user; null otherwise.
  final int? userId;

  final bool isOwner;
  final bool isSub;

  /// Optional free-text line shown under the name when no role is available.
  final String? subtitle;

  bool get hasEmail => (email ?? '').trim().isNotEmpty;
  bool get hasPhone => (phone ?? '').trim().isNotEmpty;

  /// First letter for the avatar badge.
  String get initial =>
      name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
}
