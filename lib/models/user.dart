import 'dart:convert';

class User {
  final int id;
  final String name;
  final String email;
  final bool isAdmin;

  User({
    required this.id,
    required this.name,
    required this.email,
    this.isAdmin = false,
  });

  factory User.fromJson(dynamic json) {
    if (json is String) {
      // If we just get a name string
      return User(
        id: 0,  // Temporary ID
        name: json,
        email: '',
        isAdmin: false,
      );
    }

    final Map<String, dynamic> data = json is Map ? json : jsonDecode(json);
    return User(
      id: int.tryParse(data['id']?.toString() ?? '0') ?? 0,
      name: data['name']?.toString() ?? '',
      email: data['email']?.toString() ?? '',
      isAdmin: data['is_admin'] == true,
    );
  }

  @override
  String toString() => name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is User && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
} 