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
    return User(
      id: json['id'] as int,
      name: json['name'] as String,
      email: json['email'] as String,
      phone: json['phone'] as String,
      isAdmin: json['is_admin'] as bool,
    );
  }
} 