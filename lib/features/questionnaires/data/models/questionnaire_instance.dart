import 'questionnaire_field.dart';

class SongRef {
  const SongRef({required this.title, this.artist});

  final String title;
  final String? artist;

  String get display =>
      artist == null || artist!.isEmpty ? title : '$title — $artist';

  factory SongRef.fromJson(Map<String, dynamic> json) => SongRef(
        title: json['title'] as String? ?? '',
        artist: json['artist'] as String?,
      );
}

class QuestionnaireInstance {
  const QuestionnaireInstance({
    required this.id,
    required this.name,
    required this.status,
    this.sentAt,
    this.submittedAt,
    required this.recipientName,
    required this.bookingId,
    required this.bookingName,
    this.questionnaireId,
    this.description,
    this.firstOpenedAt,
    this.lockedAt,
    this.fields = const [],
    this.responses = const {},
    this.songLookup = const {},
  });

  final int id;
  final String name;
  final String status; // sent | in_progress | submitted | locked
  final DateTime? sentAt;
  final DateTime? submittedAt;
  final String recipientName;
  final int bookingId;
  final String bookingName;
  final int? questionnaireId;
  final String? description;
  final DateTime? firstOpenedAt;
  final DateTime? lockedAt;
  final List<QuestionnaireField> fields;

  /// Decoded answers keyed by instance field id (as string).
  final Map<String, dynamic> responses;
  final Map<String, SongRef> songLookup;

  bool get isLocked => status == 'locked';
  bool get isSubmitted => status == 'submitted';

  String get statusLabel {
    switch (status) {
      case 'sent':
        return 'Sent';
      case 'in_progress':
        return 'In progress';
      case 'submitted':
        return 'Submitted';
      case 'locked':
        return 'Locked';
      default:
        return status;
    }
  }

  factory QuestionnaireInstance.fromJson(Map<String, dynamic> json) {
    final booking = json['booking'] as Map<String, dynamic>? ?? {};
    final rawFields = json['fields'] as List<dynamic>? ?? [];
    final rawResponses = json['responses'];
    final rawSongs = json['song_lookup'] as Map<String, dynamic>? ?? {};
    return QuestionnaireInstance(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String? ?? '',
      status: json['status'] as String? ?? 'sent',
      sentAt: json['sent_at'] == null
          ? null
          : DateTime.tryParse(json['sent_at'] as String),
      submittedAt: json['submitted_at'] == null
          ? null
          : DateTime.tryParse(json['submitted_at'] as String),
      recipientName: json['recipient_name'] as String? ?? 'Unknown',
      bookingId: ((booking['id'] as num?) ?? 0).toInt(),
      bookingName: booking['name'] as String? ?? '',
      questionnaireId: (json['questionnaire_id'] as num?)?.toInt(),
      description: json['description'] as String?,
      firstOpenedAt: json['first_opened_at'] == null
          ? null
          : DateTime.tryParse(json['first_opened_at'] as String),
      lockedAt: json['locked_at'] == null
          ? null
          : DateTime.tryParse(json['locked_at'] as String),
      fields: rawFields
          .map((f) => QuestionnaireField.fromJson(f as Map<String, dynamic>))
          .toList(),
      // Responses arrive keyed by int-ish field ids; normalize keys to String.
      // An empty responses set serializes as [] in PHP, so tolerate lists.
      responses: rawResponses is Map<String, dynamic>
          ? rawResponses.map((k, v) => MapEntry(k, v))
          : const {},
      songLookup: rawSongs.map(
          (k, v) => MapEntry(k, SongRef.fromJson(v as Map<String, dynamic>))),
    );
  }

  QuestionnaireInstance copyWith({String? status, DateTime? lockedAt, bool clearLockedAt = false}) {
    return QuestionnaireInstance(
      id: id,
      name: name,
      status: status ?? this.status,
      sentAt: sentAt,
      submittedAt: submittedAt,
      recipientName: recipientName,
      bookingId: bookingId,
      bookingName: bookingName,
      questionnaireId: questionnaireId,
      description: description,
      firstOpenedAt: firstOpenedAt,
      lockedAt: clearLockedAt ? null : (lockedAt ?? this.lockedAt),
      fields: fields,
      responses: responses,
      songLookup: songLookup,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QuestionnaireInstance &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
