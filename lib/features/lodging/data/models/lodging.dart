import '../../../../shared/models/displayable_attachment.dart';

class LodgingLinkedBooking {
  const LodgingLinkedBooking({required this.id, required this.name});
  final int id;
  final String name;

  factory LodgingLinkedBooking.fromJson(Map<String, dynamic> json) =>
      LodgingLinkedBooking(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String? ?? '',
      );
}

class LodgingLinkedEvent {
  const LodgingLinkedEvent({required this.id, required this.title, this.date});
  final int id;
  final String title;
  final String? date;

  factory LodgingLinkedEvent.fromJson(Map<String, dynamic> json) =>
      LodgingLinkedEvent(
        id: (json['id'] as num).toInt(),
        title: json['title'] as String? ?? '',
        date: json['date'] as String?,
      );
}

class LodgingRoom {
  const LodgingRoom({
    this.id,
    required this.label,
    this.confirmationNumber,
    this.notes,
  });

  final int? id;
  final String label;
  final String? confirmationNumber;
  final String? notes;

  factory LodgingRoom.fromJson(Map<String, dynamic> json) => LodgingRoom(
        id: (json['id'] as num?)?.toInt(),
        label: json['label'] as String? ?? '',
        confirmationNumber: json['confirmation_number'] as String?,
        notes: json['notes'] as String?,
      );

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'label': label,
        if (confirmationNumber != null) 'confirmation_number': confirmationNumber,
        if (notes != null) 'notes': notes,
      };
}

class LodgingAttachment implements DisplayableAttachment {
  const LodgingAttachment({
    required this.id,
    required this.filename,
    required this.mimeType,
    required this.fileSize,
    required this.url,
  });

  @override
  final int id;
  @override
  final String filename;
  @override
  final String mimeType;
  final int fileSize;
  @override
  final String url;

  factory LodgingAttachment.fromJson(Map<String, dynamic> json) =>
      LodgingAttachment(
        id: (json['id'] as num).toInt(),
        filename: json['filename'] as String? ?? '',
        mimeType: json['mime_type'] as String? ?? '',
        fileSize: (json['file_size'] as num?)?.toInt() ?? 0,
        url: json['url'] as String? ?? '',
      );
}

class LodgingSummary {
  const LodgingSummary({
    required this.id,
    required this.name,
    this.address,
    required this.checkInAt,
    required this.checkOutAt,
    required this.roomCount,
    required this.attachmentCount,
    this.bookingId,
    this.eventId,
  });

  final int id;
  final String name;
  final String? address;
  final String checkInAt;
  final String checkOutAt;
  final int roomCount;
  final int attachmentCount;
  final int? bookingId;
  final int? eventId;

  factory LodgingSummary.fromJson(Map<String, dynamic> json) => LodgingSummary(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String? ?? '',
        address: json['address'] as String?,
        checkInAt: json['check_in_at'] as String? ?? '',
        checkOutAt: json['check_out_at'] as String? ?? '',
        roomCount: (json['room_count'] as num?)?.toInt() ?? 0,
        attachmentCount: (json['attachment_count'] as num?)?.toInt() ?? 0,
        bookingId: (json['booking_id'] as num?)?.toInt(),
        eventId: (json['event_id'] as num?)?.toInt(),
      );

  /// Parses [checkInAt]; falls back to now on malformed input.
  DateTime get parsedCheckIn =>
      DateTime.tryParse(checkInAt) ?? DateTime.now();
}

class Lodging {
  const Lodging({
    required this.id,
    required this.name,
    this.address,
    this.latitude,
    this.longitude,
    required this.checkInAt,
    required this.checkOutAt,
    this.notes,
    this.booking,
    this.event,
    required this.rooms,
    required this.attachments,
  });

  final int id;
  final String name;
  final String? address;
  final double? latitude;
  final double? longitude;
  final String checkInAt;
  final String checkOutAt;
  final String? notes;
  final LodgingLinkedBooking? booking;
  final LodgingLinkedEvent? event;
  final List<LodgingRoom> rooms;
  final List<LodgingAttachment> attachments;

  factory Lodging.fromJson(Map<String, dynamic> json) {
    final rawRooms = json['rooms'];
    final rawAttachments = json['attachments'];
    return Lodging(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String? ?? '',
      address: json['address'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      checkInAt: json['check_in_at'] as String? ?? '',
      checkOutAt: json['check_out_at'] as String? ?? '',
      notes: json['notes'] as String?,
      booking: json['booking'] is Map<String, dynamic>
          ? LodgingLinkedBooking.fromJson(json['booking'] as Map<String, dynamic>)
          : null,
      event: json['event'] is Map<String, dynamic>
          ? LodgingLinkedEvent.fromJson(json['event'] as Map<String, dynamic>)
          : null,
      rooms: rawRooms is List
          ? rawRooms.cast<Map<String, dynamic>>().map(LodgingRoom.fromJson).toList()
          : const [],
      attachments: rawAttachments is List
          ? rawAttachments
              .cast<Map<String, dynamic>>()
              .map(LodgingAttachment.fromJson)
              .toList()
          : const [],
    );
  }

  DateTime get parsedCheckIn => DateTime.tryParse(checkInAt) ?? DateTime.now();
  DateTime get parsedCheckOut => DateTime.tryParse(checkOutAt) ?? DateTime.now();

  @override
  bool operator ==(Object other) => other is Lodging && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
