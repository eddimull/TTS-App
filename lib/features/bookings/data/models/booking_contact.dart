class BookingContact {
  const BookingContact({
    required this.id,
    required this.name,
    this.email,
    this.phone,
    this.role,
  });

  final int id;
  final String name;
  final String? email;
  final String? phone;
  final String? role;

  factory BookingContact.fromJson(Map<String, dynamic> json) {
    return BookingContact(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String,
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      role: json['role'] as String?,
    );
  }

  @override
  String toString() => 'BookingContact(id: $id, name: $name, role: $role)';
}
