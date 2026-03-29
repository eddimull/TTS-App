import 'dart:convert';

class AuthUser {
  const AuthUser({
    required this.id,
    required this.name,
    required this.email,
  });

  final int id;
  final String name;
  final String email;

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String,
      email: json['email'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
      };

  /// Convenience helpers for secure storage serialisation.
  String toJsonString() => jsonEncode(toJson());

  factory AuthUser.fromJsonString(String jsonString) =>
      AuthUser.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);

  @override
  String toString() => 'AuthUser(id: $id, name: $name, email: $email)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthUser &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          email == other.email;

  @override
  int get hashCode => Object.hash(id, email);
}
