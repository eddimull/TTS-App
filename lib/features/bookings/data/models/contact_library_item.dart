class ContactLibraryItem {
  final int id;
  final String name;
  final String? email;
  final String? phone;

  const ContactLibraryItem({
    required this.id,
    required this.name,
    this.email,
    this.phone,
  });

  factory ContactLibraryItem.fromJson(Map<String, dynamic> json) =>
      ContactLibraryItem(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        email: json['email'] as String?,
        phone: json['phone'] as String?,
      );
}
