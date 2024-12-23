class User {
  final int id;
  final String name;
  final String? email;
  final String? phone;
  final bool isAdmin;

  User({
    required this.id,
    required this.name,
    this.email,
    this.phone,
    required this.isAdmin,
  });

  factory User.fromJson(dynamic json) {
    if (json is String) {
      // Handle case where json is a string (name)
      return User(
        id: 0, // Default ID
        name: json,
        isAdmin: false,
      );
    } else if (json is Map<String, dynamic>) {
      // Handle case where json is a Map
      return User(
        id: json['id'] ?? 0,
        name: json['name'] ?? '',
        email: json['email'],
        phone: json['phone'],
        isAdmin: json['is_admin'] ?? false,
      );
    } else {
      throw FormatException('Invalid JSON format for User');
    }
  }

  @override
  String toString() => name;  // This helps in dropdowns
} 