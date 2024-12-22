class Project {
  final int id;
  final String name;
  final String? description;

  Project({
    required this.id,
    required this.name,
    this.description,
  });

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'],
      name: json['name'],
      description: json['description'],
    );
  }
} 