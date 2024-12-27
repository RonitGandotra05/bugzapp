import 'dart:convert';

class User {
  final int id;
  final String name;
  final String email;
  final String phone;
  final bool isAdmin;

  User({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.isAdmin,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    // Handle case where the response is just a name string
    if (json['name'] == null && json['id'] == null) {
      return User(
        id: -1, // Temporary ID
        name: json.toString(), // Use the string value as name
        email: '', // Empty email
        phone: '', // Empty phone
        isAdmin: false, // Default to non-admin
      );
    }

    return User(
      id: json['id'] as int,
      name: json['name'] as String,
      email: json['email'] as String,
      phone: json['phone'] as String,
      isAdmin: json['is_admin'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'phone': phone,
      'is_admin': isAdmin,
    };
  }
} 