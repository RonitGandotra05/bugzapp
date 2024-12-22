class Comment {
  final int id;
  final int bugReportId;
  final String userName;
  final String comment;
  final DateTime createdAt;

  Comment({
    required this.id,
    required this.bugReportId,
    required this.userName,
    required this.comment,
    required this.createdAt,
  });

  factory Comment.fromJson(Map<String, dynamic> json) {
    return Comment(
      id: json['id'],
      bugReportId: json['bug_report_id'],
      userName: json['user_name'],
      comment: json['comment'],
      createdAt: DateTime.parse(json['created_at']).toLocal(),
    );
  }
} 