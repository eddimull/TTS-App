class BookingContact {
  const BookingContact({
    required this.id,
    required this.name,
    this.email,
    this.phone,
    this.role,
    this.bcId,
    this.contactId,
    this.isPrimary = false,
  });

  final int id;
  final String name;
  final String? email;
  final String? phone;
  final String? role;

  /// The booking_contacts pivot row id (used for update/remove operations).
  final int? bcId;

  /// The underlying contact library id.
  final int? contactId;

  /// Whether this contact is the primary contact for the booking.
  final bool isPrimary;

  factory BookingContact.fromJson(Map<String, dynamic> json) {
    return BookingContact(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String,
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      role: json['role'] as String?,
      bcId: json['bc_id'] == null ? null : (json['bc_id'] as num).toInt(),
      contactId: json['contact_id'] == null
          ? null
          : (json['contact_id'] as num).toInt(),
      isPrimary: (json['is_primary'] as bool?) ?? false,
    );
  }

  @override
  String toString() => 'BookingContact(id: $id, name: $name, role: $role)';
}
