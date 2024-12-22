class User {
  final int id;
  final String name;
  final String email;
  final String? phone;
  final bool isAdmin;

  User({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    required this.isAdmin,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      name: json['name'],
      email: json['email'],
      phone: json['phone'],
      isAdmin: json['is_admin'],
    );
  }
} 