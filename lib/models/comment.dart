class Comment {
  final int id;
  final int bugReportId;
  final int userId;
  final String userName;
  final String comment;
  final DateTime createdAt;

  Comment({
    required this.id,
    required this.bugReportId,
    required this.userId,
    required this.userName,
    required this.comment,
    required this.createdAt,
  });

  factory Comment.fromJson(Map<String, dynamic> json) {
    return Comment(
      id: json['id'] is String ? int.parse(json['id']) : json['id'] as int,
      bugReportId: json['bug_report_id'] is String ? int.parse(json['bug_report_id']) : json['bug_report_id'] as int,
      userId: json['user_id'] is String ? int.parse(json['user_id']) : json['user_id'] as int,
      userName: json['user_name'] as String,
      comment: json['comment'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'bug_report_id': bugReportId,
      'user_id': userId,
      'user_name': userName,
      'comment': comment,
      'created_at': createdAt.toIso8601String(),
    };
  }

  Comment copyWith({
    int? id,
    int? bugReportId,
    int? userId,
    String? userName,
    String? comment,
    DateTime? createdAt,
  }) {
    return Comment(
      id: id ?? this.id,
      bugReportId: bugReportId ?? this.bugReportId,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      comment: comment ?? this.comment,
      createdAt: createdAt ?? this.createdAt,
    );
  }
} 